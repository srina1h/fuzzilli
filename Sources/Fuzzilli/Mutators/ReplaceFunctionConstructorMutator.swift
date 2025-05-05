

// A mutator that specifically targets the pattern found in the problematic test case:

// Replaces a call to the Function constructor, like `Function(expression)`,

// with code that uses the result of the expression in a different way,

// such as `String(expression)`, wrapped in a try-catch block.

// This is designed to transform the positive (crashing) test case provided

// into the negative (non-crashing) test case.

public class ReplaceFunctionConstructorMutator: BaseInstructionMutator {



    public init() {

        super.init(name: "ReplaceFunctionConstructorMutator")

    }



    // We perform the primary check inside mutate() where we have access to the ProgramBuilder

    // and can inspect the origin of the constructor variable.

    // canMutate just does a basic structural check.

    public override func canMutate(_ instr: Instruction) -> Bool {

        // Check if it's a Construct operation potentially taking one argument.

        // Construct(constructor, [arg1]) has 2 inputs.

        return instr.op is Construct && instr.numInputs == 2

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        guard instr.op is Construct, instr.numInputs == 2 else {

            // Should not happen if canMutate is correct, but double-check.

            b.adopt(instr)

            return

        }



        let constructorVar = instr.input(0)

        let argumentVar = instr.input(1)



        // Heuristic check: See if the constructor variable likely originates

        // from loading the 'Function' built-in. We look backwards moderately.

        var isLikelyFunctionConstructor = false

        if let definingInstr = b.findDefiningInstruction(for: constructorVar) {

             if let op = definingInstr.op as? LoadBuiltin, op.builtinName == "Function" {

                 isLikelyFunctionConstructor = true

             }

        }

        // Fallback: simple lookback if findDefiningInstruction isn't suitable/available

        // (Note: findDefiningInstruction is generally preferred)

        if !isLikelyFunctionConstructor {

            let lookbackLimit = 15 // How far back to check

            let currentCodeSize = b.code.count

            let startIdx = max(0, currentCodeSize - lookbackLimit)

            for i in stride(from: currentCodeSize - 1, through: startIdx, by: -1) {

                let prevInstr = b.code[i]

                if prevInstr.hasOutput && prevInstr.output == constructorVar {

                    if let op = prevInstr.op as? LoadBuiltin, op.builtinName == "Function" {

                        isLikelyFunctionConstructor = true

                    }

                    // Stop searching once we find the definition (or a redefinition)

                    break

                }

            }

        }





        if isLikelyFunctionConstructor {

            // Transformation detected: Replace Function(arg) with try{ String(arg); } catch { rethrow; }

            b.trace("Applying ReplaceFunctionConstructorMutator: Replacing Construct with Function constructor")



            b.beginTry()

            // Load the 'String' built-in.

            let stringBuiltin = b.loadBuiltin("String")

            // Call String() with the original argument. The result is discarded.

            b.callFunction(stringBuiltin, args: [argumentVar])

            b.beginCatch()

            // Rethrow any exception caught from the String() call.

            b.rethrowException()

            b.endTryCatch()



            // The original 'Construct' instruction is *not* adopted/appended,

            // effectively replacing it with the try-catch block above.



        } else {

            // If the heuristic check failed, it's likely not the target pattern.

            // Keep the original instruction unmodified.

            b.adopt(instr)

        }

    }

}
