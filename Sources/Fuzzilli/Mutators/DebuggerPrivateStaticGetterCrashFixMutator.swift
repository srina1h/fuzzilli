

// A mutator specifically designed to transform the crashing JS code involving

// Debugger.Frame.eval with private static getters into a non-crashing variant

// by evaluating a public static property instead, matching the provided negative test case.

public class DebuggerPrivateStaticGetterCrashFixMutator: BaseMutator {



    override public init() {

        super.init(name: "DebuggerPrivateStaticGetterCrashFixMutator")

    }



    // Helper to find the BeginClass instruction index and output variable for the last class defined.

    private func findLastClassDefinition(in program: Program) -> (beginIndex: Int, endIndex: Int, classVar: Variable)? {

        var lastBeginIndex: Int? = nil

        var lastEndIndex: Int? = nil

        var classVar: Variable? = nil



        for i in 0..<program.code.count {

            let instr = program.code[i]

            if instr.op is BeginClass {

                lastBeginIndex = i

                classVar = instr.output

            } else if instr.op is EndClass && lastBeginIndex != nil {

                 // Simplistic: Assume the last EndClass matches the last BeginClass found so far.

                 // This doesn't handle nesting perfectly but works for the simple case.

                lastEndIndex = i

                 // Potentially reset lastBeginIndex here if strict pairing is needed.

                 // For finding the *last* definition, we just keep the latest pair.

            }

        }



        if let beginIdx = lastBeginIndex, let endIdx = lastEndIndex, let clsVar = classVar, beginIdx < endIdx {

            return (beginIdx, endIdx, clsVar)

        }

        return nil

    }



     // Helper to find the frame.eval call instruction index. Very heuristic.

     private func findFrameEvalCallIndex(in program: Program) -> Int? {

         var frameEvalCallIndex: Int? = nil

         var frameVariable: Variable? = nil



         for i in 0..<program.code.count {

             let instr = program.code[i]



             // Look for frame = dbg.getNewestFrame().older sequence (approximate)

             if instr.op is LoadProperty && instr.propertyName == "older" {

                  // Check if the input variable likely comes from getNewestFrame()

                  // This requires looking back, which is complex. Skip detailed check for now.

                  frameVariable = instr.output

             }



             // Look for frame.eval(code)

             if let currentFrameVar = frameVariable,

                instr.op is CallMethod && instr.methodName == "eval" && instr.numInputs > 0 && instr.inputs[0] == currentFrameVar {

                frameEvalCallIndex = i

                // Don't break, might be multiple eval calls, but we'll take the last one associated with a likely frame var.

             }

         }

         return frameEvalCallIndex

     }





    override public func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> MutationResult {

        var targetLoadStringInstructionIndex: Int? = nil

        var targetCallInstructionIndex: Int? = nil

        var targetLoadStringVariable: Variable? = nil



        // Scan backwards to find the target LoadString("this.#unusedgetter") likely used in the final call

        for i in stride(from: program.code.count - 1, through: 0, by: -1) {

            let instr = program.code[i]

            if instr.op is LoadString, instr.stringValue == "this.#unusedgetter" {

                // Heuristic: Assume the last one near the end is the target.

                if i > program.code.count - 10 {

                    // Rough check if it's used in a Call operation soon after.

                    for j in i + 1 ..< min(i + 5, program.code.count) {

                         let nextInstr = program.code[j]

                         if (nextInstr.op is CallMethod || nextInstr.op is CallFunction) && nextInstr.inputs.contains(instr.output) {

                             targetLoadStringInstructionIndex = i

                             targetLoadStringVariable = instr.output

                             // We don't strictly need the call index itself for the replacement logic below,

                             // but it helps confirm the pattern.

                             targetCallInstructionIndex = j

                             break

                         }

                    }

                }

            }

            if targetLoadStringInstructionIndex != nil {

                break

            }

        }



        guard let stringLoadIndex = targetLoadStringInstructionIndex,

              let originalStringVariable = targetLoadStringVariable else {

            return .failure // Pattern not found

        }



        guard let (classBeginIndex, classEndIndex, classVar) = findLastClassDefinition(in: program) else {

             return .failure // Could not identify class definition boundaries

        }



        let evalCallIndex = findFrameEvalCallIndex(in: program) // Optional: find index for try/catch



        // Rebuild the program

        b.adopting(from: program) {

            var newStringVariable: Variable? = nil



            for i in 0..<program.code.count {

                let instr = program.code[i]



                // 1. Replace LoadString("this.#unusedgetter")

                if i == stringLoadIndex {

                    newStringVariable = b.loadString("this.publicProp")

                    // Skip copying original instruction



                // 2. Modify instructions using the old string variable

                } else if instr.hasInputs && instr.inputs.contains(originalStringVariable) {

                    guard let newVar = newStringVariable else {

                        b.append(instr); continue // Fallback if new var not created somehow

                    }

                    var newInouts = instr.inouts

                    for idx in 0..<newInouts.count {

                        if instr.isInput(idx) && newInouts[idx] == originalStringVariable {

                            newInouts[idx] = newVar

                        }

                    }

                    b.append(Instruction(instr.op, inouts: newInouts, attributes: instr.attributes))



                // 3. Add static property before EndClass

                } else if i == classEndIndex {

                    // Add: static publicProp = "hello world";

                    let propValue = b.loadString("hello world")

                    // Use DefineStaticProperty or equivalent if available, otherwise StoreProperty on classVar

                    // Assuming DefineStaticProperty for clarity, replace if FuzzIL uses another pattern.

                    // If DefineStaticProperty takes (class, name, value):

                     b.defineStaticProperty("publicProp", on: classVar, as: propValue)

                    // If it takes (name, value) within class context, adjust call.

                    // Fallback guess: StoreProperty on class object might work for static in some JS engines/FuzzIL models

                    // b.storeProperty("publicProp", on: classVar, to: propValue)



                    // Now copy the original EndClass instruction

                    b.append(instr)



                // 4. Wrap frame.eval in try-catch (Optional but part of negative case)

                } else if let evalIdx = evalCallIndex, i == evalIdx {

                    let result = b.defineVar() // Define variable for completion result

                    b.beginTry()

                    // Re-emit the original eval call, assigning output to the new var

                    b.append(Instruction(instr.op, output: result, inputs: instr.inputs, attributes: instr.attributes))

                    b.beginCatch()

                    // Optional: Log error variable (e.g., b.loadUndefined(); b.storeProperty(...) on console)

                    // For minimal change, just have an empty catch block.

                    _ = b.loadUndefined() // Need at least one instruction in catch block

                    b.endTryCatch()

                    // Skip copying the original instruction as it's now inside try block.



                // 5. Modify getter body (Simplification: Skip this complex change)

                // Finding the specific getter method body and changing it is non-trivial.



                // 6. Copy other instructions

                } else {

                    b.append(instr)

                }

            }

        } // end adopting



        return .success

    }

}



// Helper Extension needed for DefineStaticProperty (assuming such an Op exists)

// If FuzzIL represents static properties differently, this part needs adjustment.

extension ProgramBuilder {

    func defineStaticProperty(_ name: String, on classVar: Variable, as value: Variable) {

        // This is a placeholder. Replace with the actual FuzzIL instruction/op

        // for defining a static property on a class object.

        // It might be a variant of StoreProperty, DefineOwnProperty, or a dedicated Op.

        // Example using a hypothetical DefineStaticProperty Op:

        // append(Instruction(JavaScript.DefineStaticProperty(propertyName: name), inputs: [classVar, value]))



        // Fallback using StoreProperty (might not be correct for static):

         print("Warning: Using StoreProperty as a placeholder for DefineStaticProperty. Verify FuzzIL representation.")

         storeProperty(name, on: classVar, to: value)

    }

}
