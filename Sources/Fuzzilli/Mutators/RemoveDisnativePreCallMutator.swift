

// This mutator specifically targets the pattern identified in the bug report:

// A function call followed immediately by disnative on the same function.

// It removes the function call to prevent the crash, mirroring the

// primary circumvention strategy described.

// Note: This is a highly specialized mutator for a specific bug pattern.

// It does not attempt to generate the *exact* negative test case including

// comments and the alternative circumvention, as that's not typical

// for a general-purpose Fuzzili mutator.

public class RemoveDisnativePreCallMutator: BaseMutator {

    public init() {

        super.init(name: "RemoveDisnativePreCallMutator")

    }



    public override func mutate(_ program: Program, using fuzzer: Fuzzer) -> Program? {

        let b = fuzzer.makeBuilder()



        var mutated = false

        var i = 0

        while i < program.code.count {

            let currentInstr = program.code[i]



            // Check if the next instruction exists

            if i + 1 < program.code.count {

                let nextInstr = program.code[i+1]



                // Pattern: CallFunction(f, ...) followed by CallBuiltin("disnative", f, ...)

                if currentInstr.op is CallFunction,

                   let callBuiltinOp = nextInstr.op as? CallBuiltin,

                   callBuiltinOp.builtinName == "disnative" {



                    // Check if the function variable is the same for both instructions

                    // Assuming the function is the first input for both CallFunction and CallBuiltin("disnative", ...)

                    if currentInstr.numInputs > 0 && nextInstr.numInputs > 0 && currentInstr.input(0) == nextInstr.input(0) {

                        // Found the pattern. Skip the CallFunction instruction (currentInstr).

                        // Copy the CallBuiltin instruction (nextInstr).

                        b.append(nextInstr)

                        // Advance the index by 2 to skip both processed instructions

                        i += 2

                        mutated = true

                        continue // Continue to the next part of the loop

                    }

                }

            }



            // If the pattern didn't match, just copy the current instruction

            b.append(currentInstr)

            i += 1

        }



        if mutated {

            return b.finalize()

        } else {

            // No suitable pattern found in the program

            return nil

        }

    }

}
