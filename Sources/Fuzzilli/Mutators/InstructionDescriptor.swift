import Foundation



// Define InstructionDescriptor if it's not globally available in your Fuzzilli setup

// struct InstructionDescriptor { let instruction: Instruction; let index: Int; weak var program: Program? }





/// A mutator specifically designed to transform a common crashing pattern involving

/// module compilation with a null filename (via Object.defineProperty getter)

/// into a non-crashing version with a valid filename property.

public class FixModuleFilenameMutator: BaseMutator {

    let logger = Logger(withLabel: "FixModuleFilenameMutator")



    public init() {

        super.init(name: "FixModuleFilenameMutator")

    }



    override public func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Program? {

        var xVar: Variable? = nil

        var xDefRange: ClosedRange<Int>? = nil

        var definePropertyRange: ClosedRange<Int>? = nil

        var getterFuncDefRange: ClosedRange<Int>? = nil

        var compileCallIndex: Int? = nil

        var compileSrcArgVar: Variable? = nil // The var for ""

        var compileSrcArgIndex: Int? = nil // index of LoadString("")

        var stencilVar: Variable? = nil

        var instantiateCallIndex: Int? = nil

        var instantiateLoadBuiltinIndex: Int? = nil



        // Phase 1: Scan for the specific pattern

        for i in 0..<program.code.count {

            let instr = program.code[i]



            // Pattern 1: Find `var x = { module: true };`

            if xVar == nil, instr.op is BeginObjectLiteral, i + 2 < program.code.count {

                let maybeStore = program.code[i+1]

                let maybeEnd = program.code[i+2]

                if let storeOp = maybeStore.op as? StoreProperty, storeOp.propertyName == "module",

                   maybeStore.inputs.count == 2, maybeStore.inputs[1].isPrimitive, program.type(of: maybeStore.inputs[1]) == .boolean,

                   maybeEnd.op is EndObjectLiteral, maybeEnd.inputs.count == 1, maybeEnd.inputs[0] == instr.output {

                    xVar = instr.output

                    xDefRange = i...(i+2)

                }

            }



            // Pattern 2: Find `Object.defineProperty(x, "fileName", { get: function() { return null; } })`

            if let x = xVar, definePropertyRange == nil, let callOp = instr.op as? CallMethod, callOp.numInputs == 3, instr.inputs.count == 4, instr.inputs[1] == x {

                // Check if the method being called is Object.defineProperty and structure matches

                guard i > 8 else { continue }

                let optionsObjVar = instr.inputs[2] // 3rd input to CallMethod (JS arg 2) is options object

                let methodVar = instr.inputs[0]     // 1st input to CallMethod is the function object

                // Basic structural checks backwards

                if program.code[i-1].op is EndObjectLiteral, program.code[i-1].output == optionsObjVar,

                   program.code[i-6].op is LoadProperty, (program.code[i-6].op as! LoadProperty).propertyName == "defineProperty", program.code[i-6].output == methodVar,

                   program.code[i-8].op is LoadBuiltin, (program.code[i-8].op as! LoadBuiltin).builtinName == "Object"

                {

                    // Find the getter function definition range associated with the options object

                    var funcEndIdx = -1

                    var funcStartIdx = -1

                    // Search backwards from before the EndObjectLiteral for the options object

                    if let optionsBeginIdx = program.findInstruction(creating: optionsObjVar)?.index {

                        for j in stride(from: i - 2, through: optionsBeginIdx, by: -1) {

                             if program.code[j].op is EndFunctionDefinition { funcEndIdx = j }

                             if program.code[j].op is BeginFunctionDefinition {

                                funcStartIdx = j

                                break // Found start of function

                             }

                        }

                    }



                    if funcStartIdx != -1 && funcEndIdx != -1 && funcStartIdx < funcEndIdx {

                         definePropertyRange = (i-8)...i // Range includes LoadBuiltin("Object") up to CallMethod

                         getterFuncDefRange = funcStartIdx...funcEndIdx

                    }

                }

            }



            // Pattern 3: Find `compileToStencilXDR("", x)`

            if let x = xVar, compileCallIndex == nil, let callOp = instr.op as? CallFunction, callOp.numInputs == 2, instr.inputs.count == 3, instr.inputs[2] == x {

                guard i > 1 else { continue }

                let funcVar = instr.inputs[0]

                let srcVar = instr.inputs[1]

                // Check the function is compileToStencilXDR

                if program.code[i-1].op is LoadBuiltin, (program.code[i-1].op as! LoadBuiltin).builtinName == "compileToStencilXDR", program.code[i-1].output == funcVar {

                     // Check the source argument is LoadString("")

                     if let srcInstrInfo = program.findInstruction(creating: srcVar), let loadStringOp = srcInstrInfo.instruction.op as? LoadString, loadStringOp.value == "" {

                         compileCallIndex = i

                         compileSrcArgVar = srcVar

                         compileSrcArgIndex = srcInstrInfo.index

                         stencilVar = instr.output

                     }

                }

            }



            // Pattern 4: Find `instantiateModuleStencilXDR(stencil)`

            if let stencil = stencilVar, instantiateCallIndex == nil, let callOp = instr.op as? CallFunction, callOp.numInputs == 1, instr.inputs.count == 2, instr.inputs[1] == stencil {

                 guard i > 0 else { continue }

                 let funcVar = instr.inputs[0]

                  // Check the function is instantiateModuleStencilXDR

                  if program.code[i-1].op is LoadBuiltin, (program.code[i-1].op as! LoadBuiltin).builtinName == "instantiateModuleStencilXDR", program.code[i-1].output == funcVar {

                     instantiateCallIndex = i

                     instantiateLoadBuiltinIndex = i - 1

                     // Found the whole pattern

                     break // Stop scanning

                 }

            }

        }





        // Phase 2: Rebuild the program if the full pattern was found

        guard let xVar = xVar,

              let xDefLower = xDefRange?.lowerBound,

              let xDefUpper = xDefRange?.upperBound,

              let defPropLower = definePropertyRange?.lowerBound,

              let defPropUpper = definePropertyRange?.upperBound,

              let getterFuncLower = getterFuncDefRange?.lowerBound,

              let getterFuncUpper = getterFuncDefRange?.upperBound,

              let compileCallIndex = compileCallIndex,

              let compileSrcArgIndex = compileSrcArgIndex,

              let stencilVar = stencilVar,

              let instantiateCallIndex = instantiateCallIndex,

              let instantiateLoadBuiltinIndex = instantiateLoadBuiltinIndex

        else {

            // Required pattern elements not found

            return nil

        }



        // Use a new builder and adopt/copy selectively to reconstruct the program

        let newProgram = ProgramBuilder()

        newProgram.adopting(from: program) {



            // Copy instructions before original x definition

            for i in 0..<xDefLower {

                newProgram.adopt(program.code[i])

            }



            // Insert new x definition: { module: true, fileName: "valid_filename.js" }

            let fileNameVar = newProgram.loadString("valid_filename.js")

            let moduleVal = newProgram.loadBool(true)

            // Reuse the original variable 'xVar' for the new object

            newProgram.beginObjectLiteral(output: xVar)

            newProgram.storeProperty(propertyName: "module", on: xVar, with: moduleVal)

            newProgram.storeProperty(propertyName: "fileName", on: xVar, with: fileNameVar)

            newProgram.endObjectLiteral(input: xVar)



            // Determine which range to skip next: getter function or defineProperty setup

            let firstSkipLower = min(getterFuncLower, defPropLower)

            let lastSkipUpper = max(getterFuncUpper, defPropUpper)



            // Copy instructions between x definition and the start of the skipped sections

            for i in (xDefUpper + 1)..<firstSkipLower {

                 newProgram.adopt(program.code[i])

            }



            // Skip getterFuncDefRange and definePropertyRange

            // Copy instructions between the skipped sections and the LoadString("") for compile call

            for i in (lastSkipUpper + 1)..<compileSrcArgIndex {

                 newProgram.adopt(program.code[i])

            }



            // Skip LoadString("") (at compileSrcArgIndex)



            // Copy instructions between LoadString("") and the compile call itself

            for i in (compileSrcArgIndex + 1)..<compileCallIndex {

                newProgram.adopt(program.code[i])

            }



            // Rebuild the compile call with the new source string: compileToStencilXDR("export let y = 1;", x)

            let newSrcVar = newProgram.loadString("export let y = 1;")

            let originalCompileCall = program.code[compileCallIndex]

            // Ensure the adopted function variable and xVar are used correctly

            newProgram.callFunction(originalCompileCall.inputs[0], args: [newSrcVar, xVar], output: stencilVar) // Reuse stencilVar



            // Copy instructions between compile call and LoadBuiltin("instantiate...")

            for i in (compileCallIndex + 1)..<instantiateLoadBuiltinIndex {

                 newProgram.adopt(program.code[i])

            }



            // Skip LoadBuiltin("instantiate...") and CallFunction(...) for instantiation



            // Insert If/Else block checking the stencil before instantiation

            newProgram.beginIf(stencilVar) // Check if stencil compilation succeeded (non-null/non-empty)

            let instBuiltin = newProgram.loadBuiltin("instantiateModuleStencilXDR")

            newProgram.callFunction(instBuiltin, args: [stencilVar]) // Instantiate inside the 'if'

            newProgram.beginElse()

            // Optionally, add logging or other instructions in the 'else' block

            newProgram.endIf()



            // Copy remaining instructions from the original program

            for i in (instantiateCallIndex + 1)..<program.code.count {

                 newProgram.adopt(program.code[i])

            }

        }



        // Finalize the new program

        let resultingProgram = newProgram.finish()



        // Basic validation

        guard resultingProgram.size > 0 else {

            logger.error("Produced an empty program.")

            return nil

        }

        // Ensure the transformation actually happened (e.g., check program size change or content)

        guard resultingProgram.size != program.size else {

            // If sizes are the same, it's unlikely the complex transformation worked as expected

             // Or maybe the number of instructions added/removed perfectly balanced.

             // Add more robust checks if needed.

            return nil

        }





        return resultingProgram

    }

}



// Helper extensions potentially needed (ensure these or equivalents exist in your Fuzzilli environment)

extension Program {

    /// Finds the first instruction creating the given variable (checking outputs and innerOutputs).

    func findInstruction(creating variable: Variable) -> InstructionDescriptor? {

        for (index, instruction) in code.enumerated() {

            if instruction.outputs.contains(variable) || instruction.innerOutputs.contains(variable) {

                 return InstructionDescriptor(instruction, at: index, in: self)

            }

        }

        return nil

    }

}



// Define InstructionDescriptor if it's not globally available

// struct InstructionDescriptor {

//     let instruction: Instruction

//     let index: Int

//     weak var program: Program? // Use weak to avoid reference cycles if Program holds descriptors

//

//     init(_ instruction: Instruction, at index: Int, in program: Program) {

//         self.instruction = instruction

//         self.index = index

//         self.program = program

//     }

// }
