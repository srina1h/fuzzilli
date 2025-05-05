

// This mutator specifically targets the pattern where an empty `switch` statement

// exists immediately inside an `else` block. It replaces the empty `switch`

// with a simple placeholder instruction (LoadInteger(0)) to avoid the crash

// identified in the associated bug report.

//

// It transforms code like:

//

// if (...) {

//   ...

// } else {

//   switch (...) {

//   } // <-- Empty switch

// }

//

// Into:

//

// if (...) {

//   ...

// } else {

//   0; // Placeholder to keep the block non-empty

// }

//

public class ReplaceEmptySwitchInElseMutator: Mutator {



    public init() {

        super.init(name: "ReplaceEmptySwitchInElseMutator")

    }



    override public func mutate(_ program: Program, _ fuzzer: Fuzzer) -> Program? {

        var potentialMutationPoint: Int? = nil



        // Iterate through the program code to find the specific pattern:

        // BeginElse -> BeginSwitch -> EndSwitch

        // We need to check up to the third-to-last instruction.

        guard program.code.count >= 3 else { return nil }



        for i in 0 ..< program.code.count - 2 {

            let instr1 = program.code[i]

            let instr2 = program.code[i+1]

            let instr3 = program.code[i+2]



            // Check if the sequence matches BeginElse, BeginSwitch, EndSwitch

            if instr1.op is BeginElse &&

               instr2.op is BeginSwitch &&

               instr3.op is EndSwitch {

                // Found the pattern. Record the index of BeginElse.

                potentialMutationPoint = i

                // We'll mutate the first occurrence found.

                break

            }

        }



        // If the pattern was not found, we cannot mutate.

        guard let mutationPoint = potentialMutationPoint else {

            return nil

        }



        // Create a new program builder.

        let b = fuzzer.makeBuilder()



        // 1. Copy instructions before the BeginElse instruction.

        for i in 0 ..< mutationPoint {

            b.adopt(program.code[i])

        }



        // 2. Copy the BeginElse instruction itself.

        let beginElseInstr = program.code[mutationPoint]

        b.adopt(beginElseInstr)



        // 3. Instead of copying BeginSwitch and EndSwitch, insert a placeholder.

        //    LoadInteger(0) acts as a simple, valid statement like '0;' in JS,

        //    preventing the else block from being empty.

        b.loadInt(0)



        // 4. Copy instructions that came *after* the EndSwitch instruction.

        //    The original indices were mutationPoint (BeginElse),

        //    mutationPoint + 1 (BeginSwitch), mutationPoint + 2 (EndSwitch).

        //    So, we start copying from mutationPoint + 3.

        for i in mutationPoint + 3 ..< program.code.count {

             b.adopt(program.code[i])

        }



        // Finalize and return the mutated program.

        return b.finalize()

    }

}
