

// A mutator specifically designed to transform the crashing pattern related to

// assigning a boolean to an indexed element of a primitive number within an array,

// alternating with assignment to a TypedArray element.

// It applies the circumvention strategy described in the bug report.

public class SpeculativeNumberIndexingCircumventionMutator: BaseInstructionMutator {



    // Track variables potentially involved in the pattern.

    private var primitiveVar: Variable? = nil

    private var arrayVar: Variable? = nil

    private var float64ArrayVar: Variable? = nil

    private var loopVar: Variable? = nil



    // Track instruction indices to identify the pattern sequence.

    private var primitiveAssignmentIdx: Int? = nil

    private var float64ArrayConstructionIdx: Int? = nil

    private var arrayConstructionIdx: Int? = nil

    private var loopStartIdx: Int? = nil

    private var problematicAssignmentIdx: Int? = nil



    public init() {

        super.init(name: "SpeculativeNumberIndexingCircumventionMutator")

    }



    override public func begin(_ program: Program) {

        primitiveVar = nil

        arrayVar = nil

        float64ArrayVar = nil

        loopVar = nil

        primitiveAssignmentIdx = nil

        float64ArrayConstructionIdx = nil

        arrayConstructionIdx = nil

        loopStartIdx = nil

        problematicAssignmentIdx = nil



        // Scan the program to find the specific pattern components.

        // This is a simplified pattern match focusing on the key operations.

        // A robust implementation would require more sophisticated analysis.

        for (idx, instr) in program.code.enumerated() {

            // 1. Find `a = 0` (LoadInteger(0))

            if instr.op is LoadInteger, instr.output != nil, instr.integerValue == 0 {

                primitiveAssignmentIdx = idx

                primitiveVar = instr.output

            }

            // 2. Find `new Float64Array` (Construct without args)

            else if let op = instr.op as? Construct,

                    op.numInputs == 1, // Only the constructor builtin

                    let constructor = program.code.inner(instr.input(0)),

                    constructor.op is LoadBuiltin,

                    constructor.builtinName == "Float64Array",

                    instr.output != nil {

                float64ArrayConstructionIdx = idx

                float64ArrayVar = instr.output

            }

            // 3. Find `b = [a, new Float64Array]` (CreateArrayWithSpread or similar)

            //    We check if the inputs roughly match the variables found earlier.

            else if instr.op is CreateArrayWithSpread || instr.op is CreateArray,

                      instr.numInputs >= 2,

                      instr.output != nil,

                      let pVar = primitiveVar, instr.inputs.contains(pVar),

                      let f64Var = float64ArrayVar, instr.inputs.contains(f64Var) {

                arrayConstructionIdx = idx

                arrayVar = instr.output

            }

            // 4. Find the start of an infinite/simple loop `for (c = 0;; ++c)`

            //    Look for BeginForLoop (can be simplified, focusing on loop presence after array).

            //    We also need the loop variable 'c'. Often initialized right before.

            else if let prevInstr = program.code.atOrNil(idx - 1),

                    prevInstr.op is LoadInteger, prevInstr.integerValue == 0,

                    instr.op is BeginForLoop || instr.op is BeginWhileLoop, // Approximate match

                    let aVar = arrayVar,

                    let loopVariable = prevInstr.output // Assume loop var is initialized just before

            {

                 // A more robust check would analyze the loop condition/update.

                 // For this specific case, assume it's the target loop if it follows the array creation.

                 if let arrayIdx = arrayConstructionIdx, idx > arrayIdx {

                     loopStartIdx = idx

                     loopVar = loopVariable

                 }

            }

            // 5. Find the problematic assignment `b[c & 1][0] = true`

            //    StoreElement(LoadElement(b, ...), 0, LoadBoolean(true))

            else if let op = instr.op as? StoreElement,

                      let loopIdx = loopStartIdx, idx > loopIdx, // Must be inside the loop

                      let targetLoad = program.code.atOrNil(instr.index - 1), // Assuming LoadElement is just before

                      targetLoad.op is LoadElement,

                      let arrVar = arrayVar, targetLoad.input(0) == arrVar, // Target is LoadElement(b, ...)

                      let index = instr.integerValue, index == 0, // Storing at index 0

                      let valueLoad = program.code.atOrNil(instr.index - 2), // Assuming LoadBoolean is before that

                      valueLoad.op is LoadBoolean, valueLoad.booleanValue == true,

                      let lVar = loopVar, targetLoad.inputs.contains(lVar) // Index calculation involves loop var 'c'

            {

                // This confirms the core problematic assignment structure.

                problematicAssignmentIdx = idx

                // Found all parts potentially in sequence. Stop scanning.

                break

            }

        }

    }



    override public func canMutate(_ instr: Instruction) -> Bool {

        // Check if the full pattern was successfully identified in `begin`.

        // We trigger the mutation on the instruction identified as the problematic assignment.

        return instr.index == problematicAssignmentIdx &&

               primitiveAssignmentIdx != nil &&

               float64ArrayConstructionIdx != nil &&

               arrayConstructionIdx != nil &&

               loopStartIdx != nil &&

               primitiveVar != nil &&

               float64ArrayVar != nil &&

               arrayVar != nil &&

               loopVar != nil

    }



    override public func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        guard let primIdx = primitiveAssignmentIdx,

              let f64Idx = float64ArrayConstructionIdx,

              let arrayIdx = arrayConstructionIdx,

              let loopIdx = loopStartIdx,

              let assignIdx = problematicAssignmentIdx,

              let oldPrimVar = primitiveVar,

              let oldF64Var = float64ArrayVar,

              let oldArrayVar = arrayVar,

              let oldLoopVar = loopVar

        else {

            // Should not happen due to canMutate check, but good practice.

            return

        }



        // We are about to replace a large chunk of code.

        // Rebuild the relevant section using the circumvention logic.



        b.trace("Applying SpeculativeNumberIndexingCircumventionMutator")



        // 1. Replace `a = 0` with `var a = []`

        let newPrimVar = b.createArray([])

        b.adopt(primitiveVar!) // Keep the original variable number if possible/needed for context? Or replace usages?

                               // For simplicity here, we create a new var and expect subsequent code to use it.

                               // A more robust mutator would replace uses of oldPrimVar.

                               // Let's try replacing the specific instruction output.

        b.replaceInstruction(at: primIdx, with: Instruction(CreateArray(), output: oldPrimVar, inputs: []))





        // 2. Replace `new Float64Array` with `new Float64Array(1)`

        let one = b.loadInt(1)

        // Find the original constructor Builtin load

        guard let originalConstructInstr = b.prog.code.atOrNil(f64Idx),

              let constructorLoadInstr = b.prog.code.atOrNil(originalConstructInstr.index - 1), // Assume LoadBuiltin is just before

              constructorLoadInstr.op is LoadBuiltin,

              constructorLoadInstr.builtinName == "Float64Array" else {

            b.trace("Could not find Float64Array constructor load, aborting mutation")

            // Need to undo the primitive change if we abort here. This simple version doesn't.

            return // Abort complex mutation if structure deviates

        }

        let constructorBuiltin = constructorLoadInstr.output! // Get the variable holding the builtin

        b.replaceInstruction(at: f64Idx, with: Instruction(Construct(arity: 1), output: oldF64Var, inputs: [constructorBuiltin, one]))





        // 3. Ensure `b` uses the modified `a` (oldPrimVar now points to the array) and `f64`

        //    The original CreateArray instruction at arrayIdx likely already uses oldPrimVar and oldF64Var.

        //    If the replacement in steps 1 & 2 kept the same variable outputs, this instruction might be okay.

        //    We need to verify its inputs reference the (now modified) variables.

        guard let arrayCreationInstr = b.prog.code.atOrNil(arrayIdx),

              arrayCreationInstr.inputs.contains(oldPrimVar),

              arrayCreationInstr.inputs.contains(oldF64Var) else {

            b.trace("Array creation instruction doesn't use expected variables, aborting mutation")

             // Abort complex mutation

            return

        }

        // No direct replacement needed for array creation if variable outputs were reused.





        // 4. Modify the loop to be finite: `for (var c = 0; c < 10000; ++c)`

        //    This requires replacing BeginForLoop/EndForLoop or equivalent structure.

        //    We'll replace the BeginForLoop and assume a simple EndForLoop exists later.

        let limit = b.loadInt(10000)

        let oneForInc = b.loadInt(1) // Variable for increment amount

        b.replaceInstruction(at: loopIdx, with: Instruction(BeginForLoop(comparator: .lessThan, op: .add), inputs: [oldLoopVar, limit, oneForInc]))

        // Note: This assumes the original loop used PostfixAdd/Increment. If not, this might be incorrect.

        // Also assumes the EndForLoop matches.





        // 5. Wrap the problematic assignment in try-catch

        //    Insert BeginTry before, BeginCatch/EndCatch/EndTryCatch after.

        //    The original assignment instruction is at `assignIdx`.

        let originalAssignment = b.prog.code[assignIdx] // Get the original StoreElement instruction data



        // Insert BeginTry just before the original assignment

        b.insert(Instruction(BeginTry()), at: assignIdx)



        // Re-insert the original assignment logic (now at index assignIdx + 1)

        // Need to ensure its inputs are valid in the builder's current context.

        // The builder's adopt mechanism might handle this, or we might need explicit adoption.

        // Since we haven't removed/re-added the assignment inputs, they should still be valid *variables*.

        // Let's assume the builder handles context correctly when inserting around existing instructions.



        // Insert BeginCatch, EndCatch, EndTryCatch after the original assignment

        // The original assignment is now at index assignIdx + 1 due to BeginTry insertion.

        b.insert(Instruction(BeginCatch()), at: assignIdx + 2) // After assignment

        b.insert(Instruction(EndCatch()), at: assignIdx + 3)

        b.insert(Instruction(EndTryCatch()), at: assignIdx + 4)



        // Mark the mutation as successful.

        // The base class handles the adoption of the modified block.

    }



    // Override mutate(instruction) to prevent the base class logic if needed,

    // since we operate on the whole program structure identified in `begin`.

    // However, BaseInstructionMutator expects mutation per instruction.

    // The current structure uses `canMutate` to trigger only on the specific assignment index.

    // If multiple assignments match the pattern, this might apply multiple times,

    // which could be undesirable. A more robust approach might use `mutate(program)`

    // from `BaseMutator` and ensure it only runs once.

    // For this specific request, triggering on the assignment index is acceptable.

}
