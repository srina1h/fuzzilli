

/// A mutator that attempts to change the argument of a specific function call pattern

/// (resembling the crash trigger) to `undefined`. This is a targeted mutator

/// designed specifically for the provided positive/negative test case pair.

/// It looks for a call to a function where the argument might be an object literal

/// potentially causing a debugger-related crash when returned from an onStep handler,

/// and replaces that argument with `undefined`.

public class FixDebuggerThrowArgumentMutator: BaseMutator {



    public init() {

        super.init(name: "FixDebuggerThrowArgumentMutator")

    }



    override public func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Program? {

        // This mutator is highly specific to the structure observed in the crash.

        // It looks for the pattern:

        // function a(b) { ... setInterruptCallback( ... onStep = function() { return b }) ... }

        // a({ throw: ... })

        // And changes the call to:

        // a(undefined)



        var targetCallInstructionIndex: Int? = nil

        var argumentVarToReplace: Variable? = nil

        var functionVar: Variable? = nil



        // Find the function definition resembling 'a'

        var functionADefinitionIndex: Int? = nil

        var functionAVar: Variable? = nil

        for i in 0..<program.size {

            let instr = program[i]

            if instr.op is BeginFunctionDefinition {

                // Basic heuristic: Look for a function that uses setInterruptCallback and Debugger

                // This is brittle and highly specific to the example.

                var usesSetInterruptCallback = false

                var usesDebugger = false

                // Search within the function body (simplistic range check)

                for j in i + 1..<program.size {

                    let innerInstr = program[j]

                    if innerInstr.op is EndFunctionDefinition { break } // Stop at function end

                    if innerInstr.op is LoadBuiltin && (innerInstr.op as! LoadBuiltin).builtinName == "setInterruptCallback" {

                        usesSetInterruptCallback = true

                    }

                    if innerInstr.op is LoadBuiltin && (innerInstr.op as! LoadBuiltin).builtinName == "Debugger" {

                         usesDebugger = true

                    }

                    // A more robust check would involve analysing the callback passed to setInterruptCallback

                    // and seeing if it returns the function's parameter in an onStep handler.

                    // This requires much more complex analysis of the IR.

                }



                if usesSetInterruptCallback && usesDebugger {

                    functionADefinitionIndex = i

                    functionAVar = instr.output

                    break // Assume we found our target function 'a'

                }

            }

        }



        guard let funcVar = functionAVar else {

            // Could not identify the target function definition 'a' based on heuristics

            return nil

        }



        // Now find the call to this function 'a'

        for i in 0..<program.size {

            let instr = program[i]

            // Look for CallFunction where the first input is our identified function 'a'

            // and it takes exactly one argument (total 2 inputs: function + 1 arg)

            if instr.op is CallFunction && instr.numInputs == 2 && instr.input(0) == funcVar {

                 // Check if the argument seems like it could be the problematic object.

                 // Heuristic: Check if the argument is NOT undefined or a primitive.

                 // This is still imprecise. We'll try replacing it regardless if it's not undefined.

                 let argVar = instr.input(1)



                 // Attempt to find the definition of argVar to be more certain.

                 // If argVar is created by CreateObject, it's a stronger candidate.

                 var isCreatedByObjectLiteral = false

                 if let definingInstr = program.findDefiningInstruction(for: argVar) {

                     if definingInstr.op is CreateObject ||

                        definingInstr.op is CreateObjectWithSpread {

                         isCreatedByObjectLiteral = true

                     }

                 }



                 // We apply the mutation if we found the call and the argument is potentially an object

                 // or simply if it's not already undefined. Prioritize object literals.

                 let argIsUndefined = program.findDefiningInstruction(for: argVar)?.op is LoadUndefined

                 

                 if isCreatedByObjectLiteral || !argIsUndefined {

                    targetCallInstructionIndex = i

                    argumentVarToReplace = argVar // Keep track of the specific variable instance

                    functionVar = funcVar // Keep track of the function called

                    break

                 }

            }

        }



        guard let callIndex = targetCallInstructionIndex,

              let argVar = argumentVarToReplace,

              let funcArg = functionVar else {

            // Could not find the specific call `a({...})` pattern

            return nil

        }



        b.adopting(from: program) {

            // We found the target CallFunction instruction at callIndex

            let originalCallInstr = b.program[callIndex] // Get data before builder state modification



            // Ensure it's the correct instruction structure again (paranoid check)

            guard originalCallInstr.op is CallFunction,

                  originalCallInstr.numInputs == 2,

                  originalCallInstr.input(0) == funcArg, // Check if funcVar is still the same

                  originalCallInstr.input(1) == argVar else { // Check if argVar is still the same

                // Program structure might have changed unexpectedly during adoption/building

                return

            }



            // Get the variable for 'undefined'

            let undefinedVar = b.loadUndefined()



            // Create the new inputs array: [functionVar, undefinedVar]

            let newInputs = [originalCallInstr.input(0), undefinedVar]



            b.trace("FixDebuggerThrowArgumentMutator: Replacing argument \(argVar) with \(undefinedVar) in call to \(funcArg) at instruction \(callIndex)")



            // Create the new instruction, preserving outputs and attributes

            let newInstr = Instruction(originalCallInstr.op, inputs: newInputs, outputs: originalCallInstr.outputs, attributes: originalCallInstr.attributes)



            // Replace the original instruction

            b.replace(callIndex, with: newInstr)

        }



        // Return the mutated program

        return b.finalize()

    }

}
