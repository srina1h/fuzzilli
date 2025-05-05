

/// A mutator specifically designed to circumvent the bug described in

/// https://bugzilla.mozilla.org/show_bug.cgi?id=1878251

/// It transforms the triggering code pattern into a non-triggering one

/// by removing the side effect in Symbol.toPrimitive and wrapping the

/// ArrayBuffer constructor in a try-catch block within oomTest.

public class SpecificBug1878251CircumventionMutator: BaseInstructionMutator {



    public init() {

        // This mutator performs a significant transformation, so limit simultaneous mutations.

        super.init(name: "SpecificBug1878251CircumventionMutator", maxSimultaneousMutations: 1)

    }



    // We need to find a complex pattern. The easiest anchor point to check in canMutate

    // is the assignment to Symbol.toPrimitive. The full pattern check happens in mutate.

    public override func canMutate(_ instr: Instruction) -> Bool {

        return instr.op is SetProperty && instr.propertyName == "Symbol.toPrimitive"

    }



    // Helper struct to store pattern finding results

    private struct PatternInfo {

        let setPropertyInstr: Instruction

        let objectVar: Variable // The object ('x' in the example)

        let primitiveFuncVar: Variable // The function assigned to Symbol.toPrimitive

        let primitiveFuncBegin: Instruction

        let primitiveFuncEnd: Instruction

        let regexInstr: Instruction // The LoadRegExp instruction (/i/)

        let execInstr: Instruction // The CallMethod 'exec' instruction

        let oomTestCallInstr: Instruction // The CallFunction 'oomTest' instruction

        let oomTestFuncVar: Variable // The function passed to oomTest

        let oomFuncBegin: Instruction

        let oomFuncEnd: Instruction

        let arrayBufferConstructInstr: Instruction // The Construct ArrayBuffer instruction

    }



    // Helper to find the full pattern starting from a SetProperty instruction

    private func findPattern(startingAt setPropertyInstr: Instruction, in program: Program) -> PatternInfo? {

        // Basic check: Is it SetProperty [Symbol.toPrimitive]?

         guard let setPropOp = setPropertyInstr.op as? SetProperty,

               setPropOp.propertyName == "Symbol.toPrimitive",

               setPropertyInstr.numInputs == 2 else {

             return nil

         }



         let objectVar = setPropertyInstr.input(0)

         let primitiveFuncVar = setPropertyInstr.input(1)



         // 1. Find the definition of the function assigned to Symbol.toPrimitive

         //    Verify its body contains the specific side effect pattern: LoadRegExp -> CallMethod 'exec'

         guard let (primitiveFuncBegin, primitiveFuncEnd) = program.findFunctionDefinition(defining: primitiveFuncVar),

               let primitiveFuncBodyIndices = program.getInstructionIndices(in: primitiveFuncBegin, end: primitiveFuncEnd) else {

             return nil // Assigned value is not a function defined here, or structure is wrong

         }



         var regexInstr: Instruction? = nil

         var execInstr: Instruction? = nil

         for i in primitiveFuncBodyIndices {

              let currentInstr = program.code[i]

              // Look for CallMethod 'exec'

              if let callOp = currentInstr.op as? CallMethod, callOp.methodName == "exec", currentInstr.numInputs > 0 {

                  let calledOnVar = currentInstr.input(0)

                  // Check if the object called upon was defined by LoadRegExp *within this function body*

                  if let definingInstr = program.definition(of: calledOnVar),

                     definingInstr.op is LoadRegExp,

                     primitiveFuncBodyIndices.contains(definingInstr.index) {

                      regexInstr = definingInstr

                      execInstr = currentInstr

                      break // Found the target pattern

                  }

              }

         }

         // Ensure both parts of the pattern were found

         guard let foundRegexInstr = regexInstr, let foundExecInstr = execInstr else {

             return nil // Pattern /i/.exec() not found inside the function

         }



        // 2. Find a subsequent CallFunction 'oomTest'

        //    Find the Construct ArrayBuffer inside its callback function, using the same objectVar

        var oomTestCallInstr: Instruction? = nil

        var oomTestFuncVar: Variable? = nil

        var oomFuncBegin: Instruction? = nil

        var oomFuncEnd: Instruction? = nil

        var arrayBufferConstructInstr: Instruction? = nil



        // Search *after* the Symbol.toPrimitive function definition ends

        for i in primitiveFuncEnd.index + 1 ..< program.code.count {

             let currentInstr = program.code[i]

             // Is it CallFunction 'oomTest' with one argument?

             if let callOp = currentInstr.op as? CallFunction, callOp.functionName == "oomTest", currentInstr.numInputs == 1 {

                 let potentialOomFuncVar = currentInstr.input(0)

                 // Find the definition of the argument function

                 guard let (foundOomFuncBegin, foundOomFuncEnd) = program.findFunctionDefinition(defining: potentialOomFuncVar),

                       let oomFuncBodyIndices = program.getInstructionIndices(in: foundOomFuncBegin, end: foundOomFuncEnd) else {

                     continue // Argument is not a function defined here, skip this oomTest call

                 }



                 // Search inside the callback function for 'new ArrayBuffer(objectVar)'

                 for oomFuncInstrIndex in oomFuncBodyIndices {

                     let oomFuncInstr = program.code[oomFuncInstrIndex]

                      if let constructOp = oomFuncInstr.op as? Construct,

                         constructOp.constructorName == "ArrayBuffer",

                         oomFuncInstr.numInputs > 0,

                         oomFuncInstr.input(0) == objectVar { // Must use the same object

                          // Found the target Construct instruction

                          arrayBufferConstructInstr = oomFuncInstr

                          oomTestCallInstr = currentInstr

                          oomTestFuncVar = potentialOomFuncVar

                          oomFuncBegin = foundOomFuncBegin

                          oomFuncEnd = foundOomFuncEnd

                          break // Found the construct, stop searching this function body

                      }

                 }

             }

             // If we found the construct, we've found the whole pattern, stop searching the program

             if arrayBufferConstructInstr != nil {

                 break

             }

         }



         // Ensure all parts of the second stage were found

         guard let finalOomTestCall = oomTestCallInstr,

               let finalOomTestFuncVar = oomTestFuncVar,

               let finalOomFuncBegin = oomFuncBegin,

               let finalOomFuncEnd = oomFuncEnd,

               let finalArrayBufferConstruct = arrayBufferConstructInstr else {

             return nil // Didn't find the oomTest call with the specific ArrayBuffer construction

         }



        // Pattern successfully found, return all collected information

        return PatternInfo(

            setPropertyInstr: setPropertyInstr,

            objectVar: objectVar,

            primitiveFuncVar: primitiveFuncVar,

            primitiveFuncBegin: primitiveFuncBegin,

            primitiveFuncEnd: primitiveFuncEnd,

            regexInstr: foundRegexInstr,

            execInstr: foundExecInstr,

            oomTestCallInstr: finalOomTestCall,

            oomTestFuncVar: finalOomTestFuncVar,

            oomFuncBegin: finalOomFuncBegin,

            oomFuncEnd: finalOomFuncEnd,

            arrayBufferConstructInstr: finalArrayBufferConstruct

        )

    }





    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        // Verify the instruction passed by canMutate and find the full pattern

        guard let pattern = findPattern(startingAt: instr, in: b.prog) else {

            return // Full pattern not found starting from this instruction

        }



        b.trace("Applying SpecificBug1878251CircumventionMutator")



        // Use the rebuilding approach: iterate through the original program and

        // build a new one, applying modifications when specific parts are encountered.

        var currentProgIdx = 0

        while currentProgIdx < b.prog.code.count {

            let currentInstr = b.prog.code[currentProgIdx]



            if currentInstr.index == pattern.primitiveFuncBegin.index {

                // --- Rebuild the modified Symbol.toPrimitive function ---

                let op = currentInstr.op as! BeginAnyFunctionDefinition

                let params = currentInstr.parameters // Preserve original parameters, if any



                // Begin the function definition in the new program

                b.append(Instruction(op, output: pattern.primitiveFuncVar, parameters: params))



                // Add the new, simplified body: return 10;

                let loadIntVar = b.loadInt(10) // v = LoadInteger 10

                b.appendReturn(value: loadIntVar) // Return v



                // Skip all original instructions of this function in the input program

                currentProgIdx = pattern.primitiveFuncEnd.index



                // Append the corresponding End instruction for the function

                b.append(Instruction(pattern.primitiveFuncEnd.op as! EndAnyFunctionDefinition))



            } else if currentInstr.index == pattern.oomFuncBegin.index {

                 // --- Rebuild the modified oomTest callback function ---

                 let op = currentInstr.op as! BeginAnyFunctionDefinition

                 let params = currentInstr.parameters // Preserve original parameters



                 // Begin the function definition in the new program

                 b.append(Instruction(op, output: pattern.oomTestFuncVar, parameters: params))



                 // Copy instructions from the original function *before* the ArrayBuffer construct

                 for i in pattern.oomFuncBegin.index + 1 ..< pattern.arrayBufferConstructInstr.index {

                     b.append(b.prog.code[i]) // Append adopts variables automatically

                 }



                 // --- Insert the try-catch block around the ArrayBuffer construct ---

                 b.append(Instruction(BeginTry.init()))



                 // Re-emit the Construct ArrayBuffer instruction (adopting inputs/outputs)

                 let constructOp = pattern.arrayBufferConstructInstr.op

                 let inputs = pattern.arrayBufferConstructInstr.inputs.map { b.adopt($0) }

                 let outputs = pattern.arrayBufferConstructInstr.outputs.map { b.adopt($0) }

                 let attributes = pattern.arrayBufferConstructInstr.attributes

                 // Append the construct instruction *inside* the try block

                 _ = b.append(Instruction(constructOp, inputs: inputs, outputs: outputs, attributes: attributes))



                 // Add the catch block (ignoring the exception)

                 let exceptionVar = b.nextVariable() // Need a variable for the caught exception

                 b.append(Instruction(BeginCatch.init(), output: exceptionVar))

                 // EndCatch (no body needed for ignoring)

                 b.append(Instruction(EndTryCatch.init()))

                 // --- End of try-catch block ---



                // Skip the original ArrayBuffer construct instruction in the input program

                // Copy instructions from the original function *after* the ArrayBuffer construct

                for i in pattern.arrayBufferConstructInstr.index + 1 ..< pattern.oomFuncEnd.index {

                    b.append(b.prog.code[i])

                }



                // We have now processed the entire original body. Skip to the end instruction.

                currentProgIdx = pattern.oomFuncEnd.index



                // Append the corresponding End instruction for the function

                b.append(Instruction(pattern.oomFuncEnd.op as! EndAnyFunctionDefinition))



            } else if currentInstr.index > pattern.primitiveFuncBegin.index && currentInstr.index < pattern.primitiveFuncEnd.index {

                // Skip instructions that were part of the original primitive function's body

                // This case should not be strictly necessary due to the jump logic above, but acts as a safeguard.

                 () // Do nothing, advance index in the loop

            } else if currentInstr.index > pattern.oomFuncBegin.index && currentInstr.index < pattern.oomFuncEnd.index {

                // Skip instructions that were part of the original oomTest function's body

                 () // Do nothing, advance index in the loop

            }

            else {

                 // This instruction is not part of the modified functions, copy it as is

                b.append(currentInstr)

            }



            // Move to the next instruction in the original program

            currentProgIdx += 1

        }

        // The ProgramBuilder 'b' now contains the completely rebuilt, modified program.

    }

}





// Required helper extensions for Program, ProgramBuilder, Instruction

// (Ensure these or equivalent helpers are available in your Fuzzilli environment)

extension Program {

    /// Finds the Begin and End instructions defining a function for a given output variable.

    func findFunctionDefinition(defining variable: Variable) -> (beginInstruction: Instruction, endInstruction: Instruction)? {

        guard let beginInstruction = variable.definingInstruction,

              beginInstruction.op is BeginAnyFunctionDefinition else {

            // The variable is not defined by a BeginAnyFunctionDefinition instruction

            return nil

        }



        // Search forward for the matching End instruction

        var depth = 0

        for i in beginInstruction.index + 1 ..< code.count {

            let instr = code[i]

            if instr.op is BeginAnyFunctionDefinition {

                depth += 1

            } else if instr.op is EndAnyFunctionDefinition {

                if depth == 0 {

                    // Found the matching End instruction

                    return (beginInstruction, instr)

                } else {

                    // This End instruction closes a nested function

                    depth -= 1

                }

            }

        }

        // Matching End instruction not found (should not happen in well-formed programs)

        return nil

    }



     /// Returns the range of indices for instructions within a function body (excluding Begin/End).

     func getInstructionIndices(in begin: Instruction, end: Instruction) -> Range<Int>? {

         guard begin.index < end.index else { return nil }

         // The body is the instruction indices between begin and end

         return (begin.index + 1)..<end.index

     }



     /// Returns the instruction that defines the given variable, if available.

     func definition(of variable: Variable) -> Instruction? {

         return variable.definingInstruction

     }

}



extension Instruction {

    /// Convenience accessor for property name in SetProperty instructions.

    var propertyName: String? { (op as? SetProperty)?.propertyName }

    /// Convenience accessor for method name in CallMethod instructions.

    var methodName: String? { (op as? CallMethod)?.methodName }

    /// Convenience accessor for function name in CallFunction instructions.

    var functionName: String? { (op as? CallFunction)?.functionName }

    /// Convenience accessor for constructor name in Construct instructions.

    var constructorName: String? { (op as? Construct)?.constructorName }

}
