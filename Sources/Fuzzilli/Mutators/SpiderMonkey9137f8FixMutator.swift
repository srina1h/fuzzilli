

// Specific mutator to transform the SpiderMonkey crash case (commit 9137f800)

// from the problematic pattern to the fixed pattern.

public class SpiderMonkey9137f8FixMutator: BaseMutator {



    public init() {

        super.init(name: "SpiderMonkey9137f8FixMutator")

    }



    override public func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> MutationResult {

        // Check if the program structure vaguely matches the positive test case.

        // This is a heuristic check.

        guard program.code.contains(where: { $0.op is CallFunction && $0.op.opcodeName == "CallFunction" && $0.hasVisibleInput(0) && program.lookupVar($0.input(0)) == "getJitCompilerOptions"}),

              program.code.contains(where: { $0.op is CallFunction && $0.op.opcodeName == "CallFunction" && $0.hasVisibleInput(0) && program.lookupVar($0.input(0)) == "setJitCompilerOption"}),

              program.code.contains(where: { $0.op is BeginForIn }),

              program.code.contains(where: { $0.op is BeginPlainFunction }) // Check for function main()

        else {

            return .rejected // Program structure doesn't match

        }



        // If it matches, discard the old program and build the new one entirely.

        b.reset()



        let mainFunc = b.buildPlainFunction(signature: FunctionSignature.forUnknownFunction) { _ in

            // Collect keys before iterating

            let options = b.callFunction("getJitCompilerOptions")

            let keys = b.createArray([])

            b.buildForInLoop(options) { key in

                b.callMethod(on: keys, withName: "push", withArgs: [key])

            }



            // Iterate over collected keys

            b.buildForOfLoop(keys) { v16 in

                // Dummy operation

                let math = b.loadBuiltin("Math")

                let zero = b.loadInt(0)

                b.callMethod(on: math, withName: "sin", withArgs: [zero])



                // Set option within try-catch

                b.buildTryCatchFinallyLoop {

                    let minusOne = b.loadInt(-1)

                    b.callFunction("setJitCompilerOption", args: [v16, minusOne])

                } catch: { _ in

                    // Ignore errors - empty catch block

                }

            }

        }

        b.renameVariable(mainFunc, to: "main")





        // Run main multiple times

        b.buildRepeatLoop(n: 150) { _ in

             b.callFunction(mainFunc)

        }



        return .success // Successfully transformed the program

    }

}
