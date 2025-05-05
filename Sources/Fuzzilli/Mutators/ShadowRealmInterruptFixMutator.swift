

// This mutator specifically targets a known bug involving interruptIf followed by

// ShadowRealm.evaluate("m"), replacing it with a non-crashing version.

// It removes the interruptIf call and wraps the evaluate call in a try-catch,

// changing the evaluated string to "1+1".

public class ShadowRealmInterruptFixMutator: BaseMutator {



    public init() {

        super.init(name: "ShadowRealmInterruptFixMutator")

    }



    public override func mutate(_ program: Program, _ b: ProgramBuilder, _ n: Int) -> MutationResult {

        var applyCallIndex = -1

        var evaluateCallIndex = -1



        // Find the last occurrence of the specific pattern:

        // An 'apply' call (potentially related to 'interruptIf') followed immediately by

        // a 'new ShadowRealm().evaluate("m")' call.

        for i in 0..<(program.code.count - 1) {

            let instr1 = program.code[i]

            let instr2 = program.code[i+1]



            // Check if the first instruction looks like the target 'apply' call

            // and the second instruction looks like the target 'evaluate' call.

            if checkIsPotentialInterruptApplyCall(instr1, in: program) &&

               checkIsSpecificShadowRealmEvaluateCall(instr2, in: program) {

                // Store the indices of the identified instruction sequence

                applyCallIndex = i

                evaluateCallIndex = i + 1

                // We target the *last* occurrence if there are multiple.

            }

        }



        // If the specific pattern wasn't found, this mutator cannot operate.

        guard applyCallIndex != -1 else {

            return .didNotMutate

        }



        // Rebuild the program, applying the fix.

        // We use the ProgramBuilder's adopting mode to handle variable mapping.

        b.adopting(from: program) {

            // Iterate through the original program's instruction indices.

            for i in 0..<program.code.count {

                if i == applyCallIndex {

                    // Skip the 'apply' call instruction entirely.

                    // This corresponds to commenting out `y["interruptIf"].apply(y, x);`

                    continue

                } else if i == evaluateCallIndex {

                    // Replace the ShadowRealm.evaluate call with a modified version

                    // wrapped in a try-catch block.

                    let originalEvaluateCall = program.code[i]



                    // Start the try block

                    b.beginTry()



                    // Create the new string argument "1+1".

                    let newStringArg = b.loadString("1+1")



                    // Rebuild the evaluate call instruction using the new argument.

                    // We assume the original string "m" was the third input (index 2).

                    var newInputs = Array(originalEvaluateCall.inputs)



                    // Safety check: Ensure the instruction has enough inputs.

                    guard newInputs.count >= 3 else {

                        // This indicates an unexpected instruction structure, despite

                        // the earlier check. Abort the mutation safely.

                        // A more robust implementation might log this inconsistency.

                        // We'll implicitly abort by letting the adopting block fail

                        // or potentially causing a crash if not handled carefully upstream.

                        // For simplicity here, we assume the check guarantees structure.

                        // If this happens, the mutator might need adjustment based on

                        // real FuzzIL IR examples.

                         b.reset() // Clear builder state

                         for instr in program.code { b.adopt(instr) } // Restore original

                         fatalError("Invariant violation: ShadowRealm evaluate call structure changed unexpectedly.")

                    }

                    // Replace the variable holding "m" with the variable holding "1+1".

                    newInputs[2] = newStringArg



                    // Create the modified instruction using the original operation,

                    // new inputs, and original flags. Fuzzilli handles output mapping.

                    let newEvaluateCall = Instruction(originalEvaluateCall.op, inouts: newInputs, flags: originalEvaluateCall.flags)

                    b.append(newEvaluateCall)



                    // Add an empty catch block to suppress potential errors.

                    b.beginCatch()

                    // let exceptionVariable = b.catchException() // Optionally capture if needed

                    b.endTryCatch() // Complete the try-catch structure.



                } else {

                    // For all other instructions, adopt them directly into the new program.

                    b.adopt(program.code[i])

                }

            }

        } // End adopting block



        // If the adopting block completed without errors, the mutation was successful.

        return .didMutate

    }



    // Helper function to identify the specific 'new ShadowRealm().evaluate("m")' call.

    // It checks the operation type, method name, object type, and argument value.

    private func checkIsSpecificShadowRealmEvaluateCall(_ instr: Instruction, in program: Program) -> Bool {

        // Check 1: Is it a CallMethod instruction with exactly 3 inputs (method, object, argument)?

        guard instr.op is CallMethod, instr.numInputs == 3 else { return false }



        // Check 2: Was the first input (the method) loaded via LoadProperty("evaluate")?

        guard let loadMethod = program.findDefiningInstruction(for: instr.input(0)),

              let methodProp = loadMethod.op as? LoadProperty,

              methodProp.propertyName == "evaluate" else { return false }



        // Check 3: Was the second input (the object) created via CreateObject("ShadowRealm")?

        guard let createObject = program.findDefiningInstruction(for: instr.input(1)),

              let objectOp = createObject.op as? CreateObject,

              objectOp.objectName == "ShadowRealm" else { return false }



        // Check 4: Was the third input (the argument) loaded via LoadString("m")?

        guard let loadArg = program.findDefiningInstruction(for: instr.input(2)),

              let stringOp = loadArg.op as? LoadString,

              stringOp.value == "m" else { return false }



        // If all checks pass, it's the target instruction.

        return true

    }



    // Helper function to identify the call likely corresponding to 'y["interruptIf"].apply(y, x)'.

    // This check is intentionally less strict, focusing on identifying a CallMethod

    // invoking 'apply', as this seems sufficient based on the bug context.

    private func checkIsPotentialInterruptApplyCall(_ instr: Instruction, in program: Program) -> Bool {

         // Check 1: Is it a CallMethod instruction with at least 2 inputs (method, thisArgument)?

        guard instr.op is CallMethod, instr.numInputs >= 2 else { return false }



        // Check 2: Was the first input (the method) loaded via LoadProperty("apply")?

        guard let loadMethod = program.findDefiningInstruction(for: instr.input(0)),

              let methodProp = loadMethod.op as? LoadProperty,

              methodProp.propertyName == "apply" else { return false }



        // Note: A stricter check could verify that 'apply' was loaded from a property

        // named 'interruptIf', but is omitted here for broader applicability, assuming

        // any 'apply' call before the specific evaluate call might trigger the bug.

        // Example of stricter check (requires knowing 'apply' is loaded from the result of loading 'interruptIf'):

        // guard let loadInterruptIf = program.findDefiningInstruction(for: loadMethod.input(0)),

        //       let interruptIfProp = loadInterruptIf.op as? LoadProperty,

        //       interruptIfProp.propertyName == "interruptIf" else { return false }



        return true

    }

}
