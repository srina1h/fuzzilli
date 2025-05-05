

/// Specific mutator to address the `oomTest(function() { new Date(ARRAY).toString() }, ARRAY)` pattern.

///

/// It identifies this specific pattern, which involves passing an array to `new Date`

/// inside a function callback given to `oomTest`, while also passing the same array

/// as a second argument to `oomTest`.

///

/// The mutation transforms the code to avoid the implicit array-to-string conversion

/// within `new Date` inside the `oomTest` context. It achieves this by:

/// 1. Removing the array variable definition (`let x = []`).

/// 2. Removing the second array argument from the `oomTest` call.

/// 3. Replacing the `new Date(arrayVar)` call inside the `oomTest` function

///    with `new Date(0)`, using a primitive integer literal instead.

/// 4. Attempting to remove intermediate instructions that solely operated on the removed array variable.

///

/// This directly targets the transformation from the provided positive test case to

/// the first negative test case example.

public class OomTestDateArrayMutator: BaseInstructionMutator {



    public init() {

        super.init(name: "OomTestDateArrayMutator")

    }



    // We only attempt to mutate CallFunction instructions, as the pattern starts there.

    public override func canMutate(_ instr: Instruction) -> Bool {

        return instr.op is CallFunction

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        // Ensure we're looking at a CallFunction.

        guard instr.op is CallFunction else { return }



        // The specific pattern requires exactly 3 inputs for the oomTest call:

        // Input 0: The 'oomTest' builtin/function variable itself.

        // Input 1: The function definition variable (callback).

        // Input 2: The array variable passed both to the callback and oomTest.

        guard instr.numInputs == 3 else {

            return

        }



        let oomTestVar = instr.input(0)

        let functionDefVar = instr.input(1)

        let arrayVar = instr.input(2) // The 3rd input (index 2) is the array



        // 1. Verify the callee is 'oomTest'.

        guard let oomTestDef = b.definition(of: oomTestVar),

              isBuiltin(oomTestDef, named: "oomTest") else {

            return

        }



        // 2. Verify the 2nd argument is a function definition (starts with BeginPlainFunction).

        guard let functionBegin = b.definition(of: functionDefVar),

              functionBegin.op is BeginPlainFunction else {

            return

        }

        let functionBeginIdx = functionBegin.index



        // 3. Verify the 3rd argument originates from a simple Array creation (LoadArray/CreateArray).

        guard let arrayDef = b.definition(of: arrayVar),

              (arrayDef.op is LoadArray || arrayDef.op is CreateArray) else {

            return

        }

        let arrayDefIdx = arrayDef.index



        // 4. Scan the function's body for 'Construct(LoadBuiltin("Date"), arrayVar)'

        //    where 'arrayVar' is the exact same variable passed as the 3rd argument to oomTest.

        var foundTargetConstruct = false

        var targetConstructIdx: Int? = nil

        var functionEndIdx: Int? = nil // Index of the EndPlainFunction for the callback



        var balance = 0 // Tracks nested blocks/functions within the callback

        for i in functionBeginIdx + 1 ..< b.indexOf(instr) { // Scan between Begin and CallFunction

            let currentInstr = b.instruction(at: i)



            // Track function boundaries to ensure we are in the top level of the callback

            if currentInstr.op is BeginAnyFunction { balance += 1 }

            if currentInstr.op is EndAnyFunction   {

                if balance == 0 {

                    functionEndIdx = i // Found the end of our target callback function

                    break

                }

                balance -= 1

            }



            // Look for 'Construct(LoadBuiltin("Date"), arrayVar)' at the top level of the callback

            if balance == 0 && currentInstr.op is Construct && currentInstr.numInputs == 2 {

                let constructorVar = currentInstr.input(0)

                let argumentVar = currentInstr.input(1)



                // Check if constructor is 'Date' (via LoadBuiltin) and argument is our target 'arrayVar'

                if let constructorDef = b.definition(of: constructorVar),

                   isBuiltin(constructorDef, named: "Date"),

                   argumentVar == arrayVar { // Must be the *same* variable instance

                    foundTargetConstruct = true

                    targetConstructIdx = i

                    // Don't break yet; need to find the actual end of the function (functionEndIdx)

                }

            }

        }



        // Ensure we found the 'new Date(arrayVar)' pattern and the end of the callback function.

        guard foundTargetConstruct, let constructIdx = targetConstructIdx, functionEndIdx != nil else {

            // The specific pattern wasn't fully matched.

            return

        }



        // --- Pattern Matched ---

        // Proceed with the transformation to the negative test case variant 1.



        b.trace("Applying OomTestDateArrayMutator: Replacing Date(array) with Date(0) and simplifying oomTest call.")



        // Rebuild the program instruction by instruction, applying modifications.

        var varMap = VariableMap() // Maps variables from the old program to the new one



        for i in 0..<b.prog.size {

            let originalInstr = b.instruction(at: i)

            var skipInstruction = false // Flag to indicate if the current original instruction should be skipped



            // Apply specific actions based on the instruction's role in the pattern

            switch i {

            case arrayDefIdx:

                // Skip the definition of the array variable (`let x = []`)

                b.trace("Skipping original array definition: \(originalInstr)")

                skipInstruction = true

                // The output variable `arrayVar` will not be mapped or available in the new program.



            case let idx where idx > arrayDefIdx && idx < b.indexOf(instr):

                // Heuristic: Skip instructions between the array definition and the oomTest call

                // *if* they exclusively use/define the array variable. This targets things like `x.keepFailing = []`.

                // This is fragile: it might remove code needed elsewhere if the variable was used more broadly.

                // It assumes instructions operating on `arrayVar` in this region are related to the pattern being removed.

                let usesOnlyArrayVar = (originalInstr.inputs.allSatisfy { $0 == arrayVar } || originalInstr.inputs.isEmpty) &&

                                       (originalInstr.outputs.allSatisfy { $0 == arrayVar } || originalInstr.outputs.isEmpty) &&

                                       (originalInstr.innerOutputs.allSatisfy { $0 == arrayVar } || originalInstr.innerOutputs.isEmpty) &&

                                       (originalInstr.inputs.contains(arrayVar) || originalInstr.outputs.contains(arrayVar) || originalInstr.innerOutputs.contains(arrayVar))



                 if usesOnlyArrayVar && i != constructIdx { // Don't skip the Date construct itself here

                     b.trace("Skipping intermediate instruction using removed array var: \(originalInstr)")

                     skipInstruction = true

                 }





            case b.indexOf(instr): // The original oomTest call instruction

                b.trace("Rebuilding oomTest call: Removing array argument")

                // Map the 'oomTest' builtin and the function definition variable

                let newOomTestVar = varMap.get(oomTestVar)

                let newFuncDefVar = varMap.get(functionDefVar)

                // Rebuild the call using only the mapped 'oomTest' and function definition variables.

                // The original third argument 'arrayVar' is omitted.

                let callOutputs = b.callFunction(newOomTestVar, args: [newFuncDefVar])



                 // Map original outputs if any (oomTest typically doesn't have explicit outputs)

                 assert(originalInstr.numOutputs == callOutputs.count)

                 for (originalOutput, newOutput) in zip(originalInstr.outputs, callOutputs) {

                      varMap.assign(originalOutput, to: newOutput)

                 }

                skipInstruction = true // We've rebuilt the call, so skip appending the original.



            case constructIdx: // The 'new Date(arrayVar)' instruction inside the callback

                b.trace("Rebuilding Date constructor: Replacing array argument with 0")

                // Map the 'Date' constructor variable (which should be a LoadBuiltin)

                let newConstructorVar = varMap.get(originalInstr.input(0))

                // Create a 'LoadInteger 0' instruction and get its output variable

                let primitiveZeroVar = b.loadInt(0)



                // Rebuild the Construct instruction using the mapped 'Date' var and the new '0' var.

                // Adopt the original output variable for the result.

                let newOutput = b.adopt(originalInstr.output)

                varMap.assign(originalInstr.output, to: newOutput) // Map original output to new adopted output



                b.construct(newConstructorVar, args: [primitiveZeroVar], savingOutputTo: newOutput)

                skipInstruction = true // We've rebuilt it, so skip appending the original.



            default:

                // No specific action for this instruction index. It will be rebuilt below if needed.

                break

            }



            // If the instruction is marked for skipping, continue to the next iteration.

            if skipInstruction {

                // Make sure that the outputs of the skipped instruction are not mapped,

                // as they don't exist in the new program. `varMap.assign` is only called

                // when instructions are successfully rebuilt or adopted.

                continue

            }



            // --- Default Action: Rebuild the instruction with potentially mapped variables ---

            // Check if any input/output needs remapping or if the operation requires adoption.

            // This is necessary if the instruction uses a variable produced by a previously modified instruction.

             let needsRemapping = originalInstr.inputs.contains { varMap.maps($0) } ||

                                  originalInstr.outputs.contains { varMap.maps($0) } || // Should outputs be checked? Yes, for adoption.

                                  originalInstr.innerOutputs.contains { varMap.maps($0) }



            // Rebuild instruction if it needs remapping or adoption strategy requires it.

            if needsRemapping || b.shouldAdopt(originalInstr.op) {

                 // 1. Remap inputs using the varMap

                 let newInputs = originalInstr.inputs.map { varMap.get($0) }



                 // 2. Adopt outputs and map them

                 var newOutputs: [Variable] = []

                 var newInnerOutputs: [Variable] = []

                 if originalInstr.hasOutputs {

                     newOutputs = b.adopt(originalInstr.outputs)

                     for (original, new) in zip(originalInstr.outputs, newOutputs) {

                         varMap.assign(original, to: new)

                     }

                 }

                  if originalInstr.hasInnerOutputs {

                      newInnerOutputs = b.adopt(originalInstr.innerOutputs)

                     for (original, new) in zip(originalInstr.innerOutputs, newInnerOutputs) {

                         varMap.assign(original, to: new)

                     }

                  }



                 // 3. Construct the new instruction with mapped inputs and adopted outputs

                 let newInouts = newInputs + newOutputs + newInnerOutputs

                 b.append(Instruction(originalInstr.op, inouts: newInouts, flags: originalInstr.flags))

            } else {

                 // Instruction does not use any modified variables and doesn't need adoption.

                 // Append the original instruction directly. Its variables are still valid.

                 b.append(originalInstr)

            }

        }



        // If the loop completes without errors, the builder 'b' contains the mutated program.

        b.signalMutationOccurred() // Signal to Fuzzilli that the mutation was successful.

    }



    /// Helper function to check if an instruction defines a specific builtin.

    private func isBuiltin(_ instr: Instruction, named builtinName: String) -> Bool {

        guard instr.op is LoadBuiltin else { return false }

        return (instr.op as! LoadBuiltin).builtinName == builtinName

    }

}
