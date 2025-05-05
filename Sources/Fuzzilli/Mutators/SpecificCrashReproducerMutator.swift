import Foundation



/// A mutator specifically designed to transform a program exhibiting a crash

/// related to JIT recovery in String.fromCharCode (observed around SpiderMonkey

/// commit 04f7743d9469) into a non-crashing variant.

///

/// This mutator applies two potential transformations based on the analysis of the crash:

/// 1.  It finds calls to `String.fromCharCode` where the argument is the result

///     of a multiplication (`a * b`) and changes the argument to `(a * b) | 0`

///     to ensure it's treated as a 32-bit integer.

/// 2.  It finds direct calls to `evalcx()` with no arguments and replaces them

///     with `try { evalcx(''); } catch(e) {}`.

///

/// The mutator attempts to apply the first transformation. If that pattern isn't

/// found or applied, it attempts the second transformation. It only applies one

/// transformation per run.

public class SpecificCrashReproducerMutator: BaseMutator {



    private let logger: Logger



    public init() {

        self.logger = Logger(withLabel: "SpecificCrashReproducerMutator")

        super.init(name: "SpecificCrashReproducerMutator")

    }



    // Helper to check if a variable likely originates directly from LoadBuiltin("name")

    private func isLoadedBuiltin(_ variable: Variable, named builtinName: String, in b: ProgramBuilder) -> Bool {

        guard let definingInstruction = b.definition(of: variable) else { return false }

        if let loadBuiltin = definingInstruction.op as? LoadBuiltin {

            return loadBuiltin.builtinName == builtinName

        }

        // In more complex scenarios, we might need to trace variable aliases,

        // but for this specific pattern, direct definition is expected.

        return false

    }



    public override func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Program? {

        var madeChange = false



        // Adopt the program into the builder to allow modifications

        let mutatedProgram = b.adopting(from: program) {

            // --- Pass 1: Attempt to fix String.fromCharCode ---

            for i in 0..<b.numberOfInstructions {

                let instr = b.instruction(at: i)



                // Pattern: callMethod 'fromCharCode' on obj with args [arg]

                // We expect instr.numInputs == 2 (objVar, argVar)

                guard let call = instr.op as? CallMethod,

                      call.methodName == "fromCharCode",

                      instr.numInputs == 2 else {

                    continue

                }



                let objVar = instr.input(0)

                let argVar = instr.input(1)



                // Check if objVar is likely the 'String' builtin.

                guard isLoadedBuiltin(objVar, named: "String", in: b) else {

                    logger.verbose("Skipping fromCharCode at [\(i)]: Object \(objVar) is not confirmed String builtin.")

                    continue

                }



                // Find the instruction defining the argument 'argVar'.

                guard let argDefInstr = b.definition(of: argVar) else {

                     logger.verbose("Skipping fromCharCode at [\(i)]: Definition of argument \(argVar) not found.")

                    continue

                }



                // Check if the argument 'argVar' was produced by a Multiplication operation.

                guard let binaryOp = argDefInstr.op as? BinaryOperation,

                      binaryOp.op == .Mul else {

                     logger.verbose("Skipping fromCharCode at [\(i)]: Argument \(argVar) not defined by Mul (Op: \(argDefInstr.op.name)).")

                    continue

                }



                // --- Pattern Found! Apply the | 0 fix ---

                logger.info("Applying | 0 fix to String.fromCharCode argument at index \(i).")



                var coercedVar: Variable? = nil

                // Insert the fix instructions *before* the original CallMethod instruction.

                b.at(i) {

                    let zeroVar = b.loadInt(0)

                    // 'argVar' holds the result of the multiplication.

                    coercedVar = b.binary(argVar, zeroVar, with: .BitOr)

                }



                guard let finalArgVar = coercedVar else {

                     logger.error("Internal error: Failed to insert | 0 operation for fromCharCode at [\(i)].")

                    // This should not happen if b.binary works correctly.

                    continue

                }



                // The original CallMethod instruction is now at index i + 2

                // (because we inserted LoadInteger and BinaryOperation before it).

                let originalCallIndex = i + 2

                let originalCallInstr = b.instruction(at: originalCallIndex)



                // Create the new CallMethod instruction with the modified argument.

                // Adopt the original inputs/outputs to the current builder context.

                var newInouts = b.adopt(originalCallInstr.inouts)

                newInouts[1] = finalArgVar // Index 1 is the argument to fromCharCode

                let newCall = Instruction(originalCallInstr.op, inouts: newInouts)



                // Replace the original CallMethod instruction (now at index i + 2).

                b.replace(instructionAt: originalCallIndex, with: newCall)



                madeChange = true

                // Apply only one fix of this type per mutation pass.

                break

            } // End of String.fromCharCode loop



            // --- Pass 2: If no change yet, attempt to fix evalcx() ---

            if !madeChange {

                for i in 0..<b.numberOfInstructions {

                    let instr = b.instruction(at: i)



                    // Pattern: callFunction func (with no arguments)

                    // We expect instr.numInputs == 1 (only the function variable)

                    guard let call = instr.op as? CallFunction,

                          instr.numInputs == 1 else {

                        continue

                    }



                    let funcVar = instr.input(0)



                    // Check if funcVar is likely the 'evalcx' builtin.

                    guard isLoadedBuiltin(funcVar, named: "evalcx", in: b) else {

                        logger.verbose("Skipping call at [\(i)]: Callee \(funcVar) is not confirmed evalcx builtin.")

                        continue

                    }



                    // --- Pattern Found! Apply the try-catch fix ---

                    logger.info("Wrapping naked evalcx() call at index \(i) in try-catch.")



                    // Store the evalcx variable before removing the instruction.

                    let evalcxVar = funcVar



                    // Remove the original call instruction.

                    b.remove(instructionAt: i)



                    // Insert the try-catch block at the original instruction's position 'i'.

                    b.at(i) {

                        b.beginTry()

                        let emptyString = b.loadString("")

                        // Call evalcx with the empty string argument.

                        b.callFunction(evalcxVar, withArgs: [emptyString])

                        b.beginCatch()

                        // The catch block is empty as per the negative test case.

                        b.endTryCatch() // This implicitly adds EndCatch and EndTry

                    }



                    madeChange = true

                    // Apply only one fix of this type per mutation pass.

                    break

                } // End of evalcx loop

            } // End of evalcx check

        } // End of adopting block



        // Return the modified program if a change was successfully applied.

        if madeChange {

            logger.info("Mutation applied successfully.")

            return b.finalize()

        } else {

            // If neither pattern was found or applied, return nil.

            logger.info("No specific patterns found to mutate.")

            return nil

        }

    }

}


