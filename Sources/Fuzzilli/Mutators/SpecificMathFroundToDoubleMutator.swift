

/// A mutator specifically designed to change calls like `f(Math.fround(1))`

/// into `f(1.5)` to address a specific assertion failure pattern.

///

/// It looks for the pattern:

///   v1 = LoadBuiltin 'Math'

///   v2 = LoadFloat 1.0

///   v3 = CallMethod v1, 'fround', [v2]

///   vF = LoadFunction 'f' // Or BeginFunctionDefinition for 'f' output

///   CallFunction vF, [v3]

///

/// And replaces it with:

///   v1 = LoadBuiltin 'Math' // Kept if needed elsewhere

///   // v2 = LoadFloat 1.0 (skipped)

///   // v3 = CallMethod v1, 'fround', [v2] (skipped)

///   vF = LoadFunction 'f' // Or BeginFunctionDefinition for 'f' output

///   v4 = LoadFloat 1.5

///   CallFunction vF, [v4]

public class SpecificMathFroundToDoubleMutator: Mutator {



    public init() {

        super.init(name: "SpecificMathFroundToDoubleMutator")

    }



    override public func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Program? {

        var candidates: [(callIdx: Int, callInstr: Instruction, froundInstr: Instruction, loadFloatInstr: Instruction)] = []

        var functionFRef: Variable? = nil



        // 1. Find the variable for function 'f'.

        // We look for the function definition itself, as loading it might happen differently.

        for instr in program.code {

            if let op = instr.op as? BeginFunctionDefinition, op.signature.name == "f", instr.numOutputs > 0 {

                functionFRef = instr.output

                break

            }

        }

        // As a fallback, check if 'f' is loaded directly (less common for user code but possible)

        if functionFRef == nil {

             for instr in program.code {

                if let op = instr.op as? LoadFunction, op.functionName == "f", instr.numOutputs > 0 {

                     functionFRef = instr.output

                     break

                }

             }

        }



        guard let funcF = functionFRef else {

             // print("Mutator Error: Could not find function 'f'")

             return nil // Can't mutate if 'f' isn't found

        }



        // 2. Find candidate CallFunction instructions to 'f' matching the pattern

        for (idx, instr) in program.code.enumerated() {

            // Is this a call to function 'f' with one argument?

            if let callOp = instr.op as? CallFunction,

               instr.numInputs == 2, // function + 1 arg

               instr.input(0) == funcF { // Calling 'f'



                let argVar = instr.input(1) // The variable passed to 'f'



                // 3. Check if argVar comes directly from Math.fround(1.0)

                guard let froundInstr = program.findInstruction(defining: argVar),

                      let callMethodOp = froundInstr.op as? CallMethod,

                      callMethodOp.methodName == "fround",

                      froundInstr.numInputs == 2 // Math.fround(arg)

                else { continue } // Argument source is not Math.fround



                // 4. Check if the receiver of fround is Math

                guard let receiverDefInstr = program.findInstruction(defining: froundInstr.input(0)),

                      let loadBuiltinOp = receiverDefInstr.op as? LoadBuiltin,

                      loadBuiltinOp.builtinName == "Math"

                else { continue } // Receiver is not Math



                // 5. Check if the argument to fround is LoadFloat 1.0

                guard let loadFloatInstr = program.findInstruction(defining: froundInstr.input(1)),

                      let loadFloatOp = loadFloatInstr.op as? LoadFloat,

                      abs(loadFloatOp.value - 1.0) < 0.001 // Check if it's LoadFloat 1.0

                else { continue } // Argument to fround is not 1.0



                // Found a complete candidate pattern!

                candidates.append((callIdx: idx, callInstr: instr, froundInstr: froundInstr, loadFloatInstr: loadFloatInstr))

            }

        }



        if candidates.isEmpty {

            // print("Mutator Info: No matching f(Math.fround(1)) pattern found")

            return nil // No matching pattern found

        }



        // Select one candidate to mutate (e.g., the first one found)

        // Could also be random: guard let target = candidates.randomElement() else { return nil }

        let target = candidates[0]



        // Use the adopting builder to reconstruct the program with the modification

        var mutated = false

        b.adopting(from: program) {

             var replacementDone = false

             // Keep track of the instructions we intend to skip

             let instructionsToSkip = Set([target.froundInstr, target.loadFloatInstr])



             for (idx, instr) in program.code.enumerated() {

                 if idx == target.callIdx && !replacementDone {

                     // We are at the target CallFunction f instruction.

                     // Insert LoadFloat 1.5 *before* this instruction.

                     let newFloatVar = b.loadFloat(1.5)



                     // Create the modified CallFunction instruction, replacing the argument

                     var newInputs = Array(instr.inputs)

                     // Ensure the function variable is still valid in the new context

                     let currentFuncVar = b.adopt(instr.input(0))

                     newInputs[0] = currentFuncVar

                     newInputs[1] = newFloatVar // Use the new double variable

                     // Adopt outputs if any

                     let outputs = instr.outputs.map { b.adopt($0) }

                     b.append(Instruction(instr.op, inputs: newInputs, outputs: outputs, attributes: instr.attributes))



                     replacementDone = true

                     mutated = true // Mark that we performed the mutation



                 } else if !instructionsToSkip.contains(instr) {

                     // Adopt (copy) all other instructions that we are not explicitly skipping

                     b.adopt(instr)

                 }

                 // Instructions in instructionsToSkip are implicitly skipped by not adopting them

             }

        } // End adopting block



        // Return the finalized program if mutation was successful

        return mutated ? b.finalize() : nil

    }

}
