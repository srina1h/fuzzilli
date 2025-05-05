

/// Mutator that specifically targets the `String.prototype.substring(startIndex, endIndex)` pattern

/// where the `endIndex` might be problematic (like a Symbol, causing a crash in SpiderMonkey's SubstringKernel).

/// It attempts to replace the `endIndex` argument with a Number type variable or a small integer constant.

/// This mutator aims to transform the problematic pattern `v7.substring(v0, Symbol)` into something

/// like `v7.substring(v0, numberVariable)` or `v7.substring(v0, 1)`.

/// It does not attempt to replicate the exact control flow (try-catch, length checks) of the target negative case,

/// as that's complex for a single instruction mutator, but focuses on fixing the type error in the call.

/// It also does not explicitly handle the `newRope` call, assuming the primary crash stems from `substring`.

public class SpiderMonkeySubstringSymbolFixMutator: BaseInstructionMutator {



    public init() {

        super.init(name: "SpiderMonkeySubstringSymbolFixMutator", maxSimultaneousMutations: 1)

    }



    public override func canMutate(_ instr: Instruction) -> Bool {

        // Check if it's a CallMethod instruction for 'substring' with exactly 3 inputs

        // (object, startIndex, endIndex). Fuzzilli typically represents method calls this way.

        guard instr.op is CallMethod,

              let callOp = instr.op as? CallMethod,

              callOp.methodName == "substring",

              instr.numInputs == 3 else {

            return false

        }



        // We could add a check here based on the type of instr.input(2), but type information

        // can be imprecise. It's simpler to allow mutation attempts on any substring call's

        // end index and let the replacement logic find a number.

        return true

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        assert(canMutate(instr)) // Ensure the preconditions are met



        let originalEndIndexVar = instr.input(2)

        var replacementVar: Variable? = nil



        // Strategy 1: Try to find an existing Integer variable in scope.

        // This is the most likely valid type for endIndex.

        replacementVar = b.randomVariable(ofType: .integer)



        // Strategy 2: If no integer, try finding any Number variable.

        if replacementVar == nil {

           replacementVar = b.randomVariable(ofType: .number)

        }



        // Strategy 3: Use the start index variable (input 1) itself.

        // This is guaranteed to be available and often a number. Check if different.

        let startIndexVar = instr.input(1)

        if replacementVar == nil || replacementVar == originalEndIndexVar {

             if startIndexVar != originalEndIndexVar {

                 // Check if start index is likely a number/integer

                 let startIndexType = b.type(of: startIndexVar)

                 if startIndexType.Is(.integer) || startIndexType.Is(.number) {

                     replacementVar = startIndexVar

                     b.trace("Using start index variable \(startIndexVar) as replacement for substring end index.")

                 }

             }

        }



        // Strategy 4: Create a new small positive integer constant (e.g., 1 or v0 + 1 concept).

        // Using a simple constant like 1 is often safe.

        if replacementVar == nil || replacementVar == originalEndIndexVar {

            let constValue: Int64 = 1 // A simple, small, positive integer.

            replacementVar = b.loadInt(constValue)

            b.trace("Creating new constant Int(\(constValue)) as replacement for substring end index.")

        }





        // Perform the replacement only if we found/created a suitable variable

        // that is different from the original one.

        if let newEndIndexVar = replacementVar, newEndIndexVar != originalEndIndexVar {

            b.trace("Replacing substring end index \(originalEndIndexVar) with \(newEndIndexVar)")



            var newInputs = instr.inputs // Make a mutable copy

            newInputs[2] = newEndIndexVar // Replace the end index input



            // Re-create the instruction with the modified inputs.

            // adopt() handles outputs correctly.

            b.adopt(Instruction(instr.op, inouts: newInputs, flags: instr.flags))



        } else {

            // If no suitable replacement was found or created (e.g., only the original Symbol var was available),

            // copy the original instruction unchanged to avoid breaking the program structure.

            // Another mutator might handle this case differently (e.g., by deleting the instruction).

             b.trace("Could not find a suitable different number variable for substring end index, keeping original.")

            b.adopt(instr)

        }

    }

}
