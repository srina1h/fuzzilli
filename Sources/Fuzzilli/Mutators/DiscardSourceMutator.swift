

/// A mutator that specifically targets the `newGlobal({discardSource: true})` pattern

/// and changes the boolean value to `false`. This is designed to turn a crashing

/// test case (where `discardSource: true` causes an assertion) into a non-crashing one.

///

/// It looks for the following Fuzzilli IL pattern:

///

/// v_true = LoadBoolean(value: true)

/// ...

/// v_obj = CreateObject(propertyNames: ["...", "discardSource", ...], inputs: [..., v_true, ...])

/// ...

/// v_newGlobal = LoadBuiltin("newGlobal") // Or similar way to get 'newGlobal'

/// ...

/// CallFunction(v_newGlobal, [v_obj, ...])

///

/// And replaces the `LoadBoolean(value: true)` with `LoadBoolean(value: false)`.

public class DiscardSourceMutator: Mutator {



    public init() {}



    public func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Int {

        var candidates: [(loadBoolInstrIndex: Int, loadBoolInstr: Instruction)] = []



        // Scan the program to find potential mutation candidates by looking for the LoadBoolean(true)

        // that eventually feeds into the target pattern.

        for i in 0..<program.size {

            let instr = program.instructions[i]



            // Is this LoadBoolean(value: true)?

            guard let loadBooleanOp = instr.op as? LoadBoolean,

                  loadBooleanOp.value == true,

                  instr.hasOutputs else { continue }



            let trueVar = instr.output



            // Now, check if this variable is used in the way we expect.

            // This requires forward scanning or analyzing the program's use-def chains.

            // A simpler approach for this specific mutator is to scan for the CallFunction

            // first and then work backwards, as done in the thought process. Let's stick to that.

        }



        // Reset candidates and use the backwards-scan approach

        candidates = []



        // Scan backwards from CallFunction instructions

        for i in (0..<program.size).reversed() {

            let callInstr = program.instructions[i]



            // 1. Is it a CallFunction?

            guard callInstr.op is CallFunction, callInstr.numInputs >= 2 else { continue }



            // 2. Is the callee 'newGlobal'? (Check definition)

            // Use Fuzzilli's built-in way to find definitions.

            guard let calleeDefIdx = program.code.findDefiningInstruction(for: callInstr.input(0)),

                  let loadBuiltinOp = program.code[calleeDefIdx].op as? LoadBuiltin,

                  loadBuiltinOp.builtinName == "newGlobal" else { continue }



            // 3. Is the first argument defined by CreateObject?

            let optionsVar = callInstr.input(1)

            guard let createObjectIdx = program.code.findDefiningInstruction(for: optionsVar),

                  let createObjectInstr = program.code[safe: createObjectIdx], // Use safe subscripting

                  let createObjectOp = createObjectInstr.op as? CreateObject else { continue }



            // 4. Does CreateObject have 'discardSource' property?

            var discardSourceValueVar: Variable? = nil

            var discardSourcePropIndex = -1

            for propIdx in 0..<createObjectOp.propertyNames.count {

                if createObjectOp.propertyNames[propIdx] == "discardSource" {

                    // Ensure the index is valid for inputs array

                    guard propIdx < createObjectInstr.numInputs else { break }

                    discardSourceValueVar = createObjectInstr.input(propIdx)

                    discardSourcePropIndex = propIdx

                    break

                }

            }

            guard let valueVar = discardSourceValueVar, discardSourcePropIndex != -1 else { continue }



            // 5. Is the value for 'discardSource' defined by LoadBoolean(value: true)?

            guard let loadBooleanInstrIdx = program.code.findDefiningInstruction(for: valueVar),

                  let loadBooleanInstr = program.code[safe: loadBooleanInstrIdx], // Use safe subscripting

                  let loadBooleanOp = loadBooleanInstr.op as? LoadBoolean,

                  loadBooleanOp.value == true else { continue }



            // Found a candidate! Store the index and instruction of the LoadBoolean to change.

            // Avoid adding duplicates if the same LoadBoolean is part of multiple patterns.

            if !candidates.contains(where: { $0.loadBoolInstrIndex == loadBooleanInstrIdx }) {

                 candidates.append((loadBoolInstrIndex: loadBooleanInstrIdx, loadBoolInstr: loadBooleanInstr))

            }

        }





        guard !candidates.isEmpty else {

            // No matching pattern found

            return 0 // No mutations applied

        }



        // Select one candidate to mutate (e.g., randomly)

        let target = candidates.randomElement()!

        // Fuzzilli Builder API expects us to rebuild the program



        // Rebuild the program, replacing the targeted LoadBoolean instruction

        for idx in 0..<program.size {

             if idx == target.loadBoolInstrIndex {

                 // Insert the modified instruction instead of adopting the original

                 let originalInstr = target.loadBoolInstr

                 let replacementOp = LoadBoolean(value: false)

                 // Reuse outputs and inputs from the original instruction

                 // This ensures the variable defined by the original instruction is still defined correctly

                 // and subsequent uses remain valid.

                 b.append(Instruction(replacementOp, outputs: originalInstr.outputs, inouts: originalInstr.inputs))

             } else {

                 // Adopt (copy) the instruction from the original program

                 b.adopt(program.instructions[idx])

             }

         }



        // Return the number of mutations applied (we only apply one change here)

        return 1

    }

}



// Helper extension for safe array access might be useful depending on context

extension Array {

    subscript(safe index: Int) -> Element? {

        return indices.contains(index) ? self[index] : nil

    }

}



// Note: Ensure Fuzzilli's Program/Code provides `findDefiningInstruction` and that

// accessing `program.code[index]` or `program.instructions[index]` is the correct way

// to get instructions based on the context. The use of `program.instructions` and

// `program.code` might need harmonization based on the specific Fuzzilli version.

// The core logic of finding the pattern and replacing the LoadBoolean(true) remains the same.
