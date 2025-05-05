

/// A highly specific mutator designed to transform the FuzzIL representation

/// of the positive (crashing) test case into the negative (non-crashing) one

/// described in the problem description.

///

/// This mutator focuses on:

/// 1. Changing the initial value of the array element at index 1 from 0 to 1.

/// 2. Changing the value stored at index 255 from `array[255] % 4` to `loopVar % 4`.

///

/// IMPORTANT: This mutator does NOT perform instruction reordering (moving the

/// store before the Uint8Array construction), which was also part of the

/// manual fix analysis. Reordering is significantly more complex and typically

/// requires a ProgramMutator capable of larger code restructuring.

/// This mutator relies on the specific structure and variable patterns

/// observed in the provided example.

public class SpecificCrashTransformerMutator: BaseInstructionMutator {



    public init() {

        super.init(name: "SpecificCrashTransformerMutator", maxSimultaneousMutations: 1)

    }



    // Check if the instruction is the target StoreElement instruction:

    // StoreElement v17, 255, result_of_mod

    public override func canMutate(_ instr: Instruction) -> Bool {

        guard instr.op is StoreElement,

              instr.numInputs == 3,

              let index = instr.input(1).integer, index == 255 else {

            return false

        }

        // Further checks involving tracing back inputs are done in mutate()

        // as it requires program context not readily available here.

        return true

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        // --- Verify Instruction Pattern ---

        guard instr.op is StoreElement, // Already checked in canMutate

              instr.numInputs == 3,

              let indexVar = instr.input(1).integer, indexVar == 255 else { // Already checked

            return

        }



        let v17 = instr.input(0) // The array being modified (e.g., v17)

        let modResult = instr.input(2) // The value being stored



        // --- Trace Back Inputs ---



        // 1. Find the Mod instruction producing modResult

        guard let modInstr = b.findInstruction(defining: modResult),

              modInstr.op is Mod,

              modInstr.numInputs == 2 else {

            return // Value doesn't come from a Mod instruction

        }



        // 2. Find the LoadElement instruction feeding the Mod

        let loadElemResult = modInstr.input(0)

        guard let loadElemInstr = b.findInstruction(defining: loadElemResult),

              loadElemInstr.op is LoadElement,

              loadElemInstr.numInputs == 2,

              loadElemInstr.input(0) == v17, // Must load from the same array v17

              loadElemInstr.input(1).integer == 255 // Must load the same index 255

        else {

            return // Mod input is not LoadElement v17[255]

        }



        // 3. Find the LoadInteger 4 feeding the Mod

        let fourVar = modInstr.input(1)

        guard let loadConst4Instr = b.findInstruction(defining: fourVar),

              loadConst4Instr.op is LoadInteger,

              loadConst4Instr.integer == 4 else {

            return // Mod divisor is not LoadInteger 4

        }



        // 4. Find the CreateArrayWith instruction defining v17

        guard let createArrayInstr = b.findInstruction(defining: v17),

              let createArrayOp = createArrayInstr.op as? CreateArrayWith,

              createArrayOp.initialValues.count >= 2, // Ensure index 1 exists

              createArrayOp.initialValues[1] == 0 // Check if v17[1] is initially 0

        else {

             // Cannot find the expected array creation or v17[1] is not 0

             return

        }



        // 5. Find the outer loop variable 'v1'. Search backwards heuristically.

        var v1: Variable? = nil

        var currentBlockDepth = b.currentBlockDepth

        // Search only within the current function or global scope to find the loop variable

        guard let startIndex = b.indexOf(instr) else { return }

        for i in (b.currentFunction?.codeStart ?? 0 ..< startIndex).reversed() {

             let prevInstr = b.instruction(at: i)

             if prevInstr.isBlockGroupEnd { currentBlockDepth += 1 }



             // Assuming the target loop is the outermost loop in the current context (depth 1)

             if prevInstr.op is BeginFor && currentBlockDepth == 1 && prevInstr.numOutputs > 0 {

                 v1 = prevInstr.output // Found the loop variable (e.g., v1)

                 break

             }

             if prevInstr.isBlockGroupStart { currentBlockDepth -= 1 }

        }

        guard let loopVarV1 = v1 else {

            // Cannot find the loop variable 'v1' needed for the transformation

            return

        }



        // --- Apply Transformations ---

        b.trace("Applying SpecificCrashTransformerMutator to \(instr)")



        // Transformation 1: Change v17[1] from 0 to 1.

        // Instead of modifying CreateArrayWith (which is hard mid-build),

        // insert a StoreElement instruction right after the array creation.

        let one = b.loadInt(1)

        let index1 = b.loadInt(1)

        // Ensure we insert correctly relative to the builder's current state

        if let createArrayIdx = b.indexOf(createArrayInstr), createArrayIdx < b.currentIndex {

             // We need to insert relative to the *original* program structure if possible,

             // or ensure the insertion happens logically after the creation in the new build.

             // This is complex. A simple approach: just emit it *before* the current instruction.

             // This might not be semantically correct if other uses of v17[1] exist between

             // its creation and this mutator's target instruction.

             // For this specific case, assume it's safe to insert before the current block.

             b.insertBefore(instr, Instruction(StoreElement(), inputs: [v17, index1, one]))

             b.trace("Inserted StoreElement \(v17)[\(index1)] = \(one)")

        } else {

            // Fallback or error - CreateArray instruction not found before current index?

             b.log(.warning, "Could not reliably insert StoreElement to modify v17[1]; skipping this part.")

            // If we cannot reliably modify v17[1], maybe abort the whole mutation?

            return

        }





        // Transformation 2: Replace the value stored in the target StoreElement.

        // Original: StoreElement v17, 255, (Mod (LoadElement v17, 255), 4)

        // New:      StoreElement v17, 255, (Mod v1, 4)



        // Calculate v1 % 4. We already have loopVarV1 and fourVar.

        let newModResult = b.mod(loopVarV1, fourVar)



        // Create the new StoreElement instruction using the new value.

        // Use the original inputs for the array (v17) and index (input(1))

        let newStoreElement = Instruction(StoreElement(), inputs: [instr.input(0), instr.input(1), newModResult])



        // Replace the original instruction ('instr') with the modified one.

        b.replace(instr, with: newStoreElement)

        b.trace("Replaced \(instr) with \(newStoreElement)")



        // Note: Reordering is NOT performed by this mutator.

    }

}
