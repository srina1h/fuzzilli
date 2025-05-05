import Fuzzilli // Assuming Fuzzilli modules are properly imported



/// A mutator that specifically targets the pattern involving creating an Array Iterator,

/// accessing its `__proto__`, and calling `Object.defineProperty` on that prototype

/// with the property "return". It removes these specific instructions (and the intermediate

/// prototype access) to potentially circumvent crashes related to iterator prototype modification,

/// mirroring the transformation from the provided positive to negative test case.

public class RemoveIteratorProtoModificationMutator: Mutator {



    public init() {

        super.init(name: "RemoveIteratorProtoModificationMutator")

    }



    override public func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> MutationResult {

        var iteratorCreationIdx: Int? = nil

        var iteratorVar: Variable? = nil

        var protoAccessIdx: Int? = nil

        var protoVar: Variable? = nil

        var definePropertyCallIdx: Int? = nil



        // Scan the program code to find the specific sequence of instructions.

        for (idx, instr) in program.code.enumerated() {



            // State 1: Looking for iterator creation.

            // We are looking for an instruction that creates the iterator, like `[].values()`

            // This might be represented as a CallMethod("values") on an array,

            // or potentially a dedicated CreateArrayIterator instruction.

            // We also check that we haven't already found the start of the pattern.

            if iteratorVar == nil {

                // Heuristic check: Is it a method call named "values" producing one output?

                // This is specific to the example; a more robust check might be needed for general cases.

                if instr.numOutputs == 1 && (instr.op is CallMethod && instr.methodName == "values") /* || instr.op is CreateArrayIterator */ {

                    iteratorCreationIdx = idx

                    iteratorVar = instr.output

                    // Found the first part, continue to the next instruction/state.

                    continue

                }

            }



            // State 2: Looking for GetProperty("__proto__") on the found iterator variable.

            // This state is active only after an iterator variable has been identified.

            else if protoVar == nil {

                // Check if the current instruction gets "__proto__" from our iteratorVar.

                if let currentIterVar = iteratorVar,

                   instr.op is GetProperty && instr.getPropertyName == "__proto__" &&

                   instr.numInputs == 1 && instr.input(0) == currentIterVar && instr.numOutputs == 1 {

                    protoAccessIdx = idx

                    protoVar = instr.output

                    // Found the second part, continue to the next instruction/state.

                    continue

                }

                // Optional: If iteratorVar is redefined or used unexpectedly before proto access, reset state?

                // For this specific mutator, we assume a direct sequence.

            }



            // State 3: Looking for the Object.defineProperty call on the found prototype variable.

            // This state is active only after both iterator and its prototype variable have been identified.

            else if definePropertyCallIdx == nil {

                 // Check if it's a Call instruction (Function or Method) using the protoVar as the first argument.

                 if let currentProtoVar = protoVar,

                    (instr.op is CallFunction || instr.op is CallMethod) &&

                    // If it's a CallMethod, ensure the method name is "defineProperty".

                    (instr.op is CallMethod ? instr.methodName == "defineProperty" : true) &&

                    instr.numInputs >= 3 && // Needs at least obj, prop, descriptor.

                    instr.input(0) == currentProtoVar {



                     // Verify the second argument is the string "return".

                     // This requires finding the instruction that defined instr.input(1).

                     var isReturnString = false

                     if let (_, definingInstr) = findDefiningInstruction(for: instr.input(1), in: program.code, searchUpTo: idx) {

                         if definingInstr.op is LoadString && definingInstr.string == "return" {

                             isReturnString = true

                         }

                     }



                     // If it's the correct call with the correct property name...

                     if isReturnString {

                         // We've found the complete pattern.

                         definePropertyCallIdx = idx

                         // Break the loop as we've found what we were looking for.

                         break

                     }

                 }

            }



             // Heuristic Scope Reset: If we encounter a block boundary before finding the

             // entire pattern, reset the search. This helps ensure the pattern occurs

             // within a single, relevant scope (like the 'with' block in the example).

            if instr.isBlockEnd || instr.isBlockBegin {

                if definePropertyCallIdx == nil { // Only reset if the full pattern wasn't found yet.

                    iteratorCreationIdx = nil

                    iteratorVar = nil

                    protoAccessIdx = nil

                    protoVar = nil

                }

            }

        } // End of instruction iteration loop



        // Check if all three parts of the pattern were found successfully.

        if let iterIdx = iteratorCreationIdx, let protoIdx = protoAccessIdx, let defPropIdx = definePropertyCallIdx {

            let indicesToRemove: Set<Int> = [iterIdx, protoIdx, defPropIdx]



            // Attempt to build the modified program.

            b.adopting(from: program) {

                var currentCode = Code()

                var instructionsRemovedCount = 0

                // Iterate through the original program's instructions.

                for (idx, instr) in program.code.enumerated() {

                    // Keep the instruction only if its index is not marked for removal.

                    if !indicesToRemove.contains(idx) {

                        currentCode.append(b.adopt(instr))

                    } else {

                        instructionsRemovedCount += 1

                    }

                }



                // Finalize the new program in the builder only if:

                // 1. We actually removed the expected number of instructions (3).

                // 2. The resulting program code is not empty.

                if instructionsRemovedCount == indicesToRemove.count && !currentCode.isEmpty {

                    b.finalize(with: currentCode)

                }

                // If conditions aren't met, finalize is not called, builder remains empty, leading to .failure.

            }



            // Return success if the builder contains a valid program, failure otherwise.

            return b.hasProgram ? .success : .failure

        } else {

            // The specific instruction pattern was not found in the program.

            return .failure

        }

    }



    /// Helper function to find the instruction that defines a given variable.

    /// Searches backwards from the `searchUpTo` index in the provided `code`.

    /// Returns the index and the instruction tuple if found, otherwise `nil`.

    private func findDefiningInstruction(for variable: Variable, in code: Code, searchUpTo: Int) -> (Int, Instruction)? {

        // Ensure the starting index for the backward search is valid.

        let startSearchIndex = min(searchUpTo, code.count) - 1

        guard startSearchIndex >= 0 else { return nil }



        for i in stride(from: startSearchIndex, through: 0, by: -1) {

            let instr = code[i]

            // Check if the variable is in the instruction's regular outputs.

            if instr.outputs.contains(variable) {

                return (i, instr)

            }

            // Check if the variable is in the instruction's inner outputs (for blocks).

            if instr.hasInnerScope && instr.innerOutputs.contains(variable) {

                 return (i, instr)

            }

        }

        // Variable definition not found within the searched range.

        return nil

    }

}
