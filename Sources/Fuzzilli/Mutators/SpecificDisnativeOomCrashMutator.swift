

// Specific mutator to transform the positive test case (disnative OOM crash)

// into the negative test case (avoids the crash).

public class SpecificDisnativeOomCrashMutator: BaseMutator {



    public init() {

        super.init(name: "SpecificDisnativeOomCrashMutator")

    }



    public override func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Program? {

        // This mutator is highly specific and looks for the exact pattern.

        // It's less general than typical Fuzzili mutators.



        var functionDefInstrIndex: Int? = nil

        var functionVar: Variable? = nil

        var functionCallInstrIndex: Int? = nil

        var oomCallInstrIndex: Int? = nil

        var disnativeLoadInstrIndex: Int? = nil

        var disnativeVar: Variable? = nil

        var disnativeCallInstrIndex: Int? = nil



        // Scan for the instruction pattern

        for (i, instr) in program.code.enumerated() {

            // 1. Find `function f() {}` - Look for BeginPlainFunction immediately followed by EndPlainFunction

            if i + 1 < program.code.endIndex && instr.op is BeginPlainFunction && program.code[i+1].op is EndPlainFunction {

                if instr.numOutputs == 1 {

                    functionDefInstrIndex = i

                    functionVar = instr.output

                }

            }

            // 2. Find `f();` - CallFunction using the variable defined above

            else if let fVar = functionVar, instr.op is CallFunction, instr.numInputs > 0 && instr.input(0) == fVar {

                functionCallInstrIndex = i

            }

            // 3. Find `this.oomAtAllocation(5);` - Look for CallMethodProperty "oomAtAllocation" on likely 'this'

            //    (We approximate 'this' by looking for a CallMethodProperty with that name)

            else if instr.op is CallMethodProperty, let op = instr.op as? CallMethodProperty, op.propertyName == "oomAtAllocation" {

                // Basic check: ensure the call happens after the function definition/call

                 if functionCallInstrIndex != nil {

                    oomCallInstrIndex = i

                }

            }

            // 4. Find `let g = this.disnative;` - Look for LoadProperty "disnative" on likely 'this'

            //    (We approximate 'this' by looking for LoadProperty with that name)

            else if instr.op is LoadProperty, let op = instr.op as? LoadProperty, op.propertyName == "disnative" {

                // Basic check: ensure the load happens after the oom call

                if oomCallInstrIndex != nil && instr.numOutputs == 1 {

                     disnativeLoadInstrIndex = i

                     disnativeVar = instr.output

                 }

            }

            // 5. Find `g(f);` - CallFunction using the disnative var and the function var

            else if let dVar = disnativeVar, let fVar = functionVar, instr.op is CallFunction, instr.numInputs > 1 && instr.input(0) == dVar && instr.input(1) == fVar {

                 // Basic check: ensure the call happens after the disnative load

                 if disnativeLoadInstrIndex != nil {

                    disnativeCallInstrIndex = i

                 }

            }

        }





        // Check if the full pattern in the expected order was found

        guard let fDefIdx = functionDefInstrIndex,

              let fVar = functionVar,

              let fCallIdx = functionCallIndex,

              let oomIdx = oomCallIndex,

              let dLoadIdx = disnativeLoadInstrIndex,

              let dVar = disnativeVar,

              let dCallIdx = disnativeCallInstrIndex,

              fDefIdx < fCallIdx, fCallIdx < oomIdx, oomIdx < dLoadIdx, dLoadIdx < dCallIdx // Ensure order

        else {

            // Pattern not found or out of order

            return nil

        }



        // Pattern found, now rebuild the program with modifications

        b.adopting(from: program) {

            var mutated = false

            for (i, instr) in program.code.enumerated() {

                if i == fDefIdx {

                    // Replace function body: function f() { return 1 + 1; }

                    let newFunc = b.loadBuiltin("Function")

                    let signature = FunctionSignature.forUnknownFunction // Or more specific if known

                    b.buildPlainFunction(with: signature, defining: fVar) { args in

                        let v1 = b.loadInt(1)

                        let v2 = b.loadInt(1)

                        let sum = b.binary(v1, v2, with: .Add)

                        b.doReturn(sum)

                    }

                    mutated = true

                    // Skip the original EndPlainFunction instruction which is at i + 1

                } else if i == fDefIdx + 1 {

                     // Skip original EndPlainFunction

                     continue

                } else if i == oomIdx {

                    // Remove the oomAtAllocation call by skipping it

                    b.trace("SpecificDisnativeOomCrashMutator: Removed oomAtAllocation call.")

                    mutated = true

                    continue // Don't append this instruction

                } else if i == dCallIdx {

                    // Wrap the g(f) call

                    b.trace("SpecificDisnativeOomCrashMutator: Wrapping disnative call.")



                    // Ensure the variables are available in the current scope for the builder

                    guard let currentG = b.findVariable(named: dVar.identifier),

                          let currentF = b.findVariable(named: fVar.identifier) else {

                        // If variables are somehow lost, bail out or just adopt original

                        b.adopting(program.code[i...]) // Adopt remaining instructions

                        return // Exit the building closure

                    }



                    let typeOfG = b.typeOf(currentG)

                    let functionString = b.loadString("function")

                    let isFunction = b.compare(typeOfG, functionString, with: .strictEqual)



                    b.buildIf(isFunction) {

                        b.buildTryCatchFinally(tryBody: {

                            // Recreate the original call g(f) inside the try block

                            b.callFunction(currentG, args: [currentF]) // Use the adopted variables

                        }, catchBody: { _ in

                            // Empty catch block

                            b.trace("SpecificDisnativeOomCrashMutator: Added empty catch block.")

                        })

                    }

                    mutated = true

                } else {

                    // Adopt all other instructions unmodified

                    b.adopt(instr)

                }

            } // End of instruction loop



            guard mutated else {

                // Should not happen if pattern was matched, but as a safeguard

                return // Indicate no mutation occurred in the rebuild phase

            }

        } // End of adopting closure



        // Return the finalized program if mutation occurred

        return b.finalize()

    }

}
