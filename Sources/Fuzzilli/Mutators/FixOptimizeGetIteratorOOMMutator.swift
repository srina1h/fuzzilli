import Foundation



/// A mutator that specifically targets the pattern involving oomAtAllocation

/// followed by empty array destructuring from an IIFE (`let [] = (() => [])()`),

/// which crashes certain JS engine versions due to JIT issues with OptimizeGetIterator fuse.

/// It attempts to transform the code to match the provided non-crashing example:

/// - Removes the `oomAtAllocation` call.

/// - Changes the IIFE to return a non-empty array (e.g., `[1]`).

/// - Introduces an intermediate variable for the IIFE result.

/// - Changes the destructuring to match the new array (e.g., `let [x] = result`).

public class FixOptimizeGetIteratorOOMMutator: Mutator {



    // Store indices found during the scan phase

    private var oomInstructionIdx: Int? = nil

    private var destructInstructionIdx: Int? = nil

    private var createEmptyArrayInstrIdx: Int? = nil // Inside the IIFE

    private var returnInstrIdx: Int? = nil // Inside the IIFE

    private var iifeCallInstrIdx: Int? = nil // The Call instruction for the IIFE

    private var functionDefinitionInstrIdx: Int? = nil // The BeginAnyFunction for the IIFE

    private var functionEndInstrIdx: Int? = nil // The EndAnyFunction for the IIFE



    public init() {

        super.init(name: "FixOptimizeGetIteratorOOMMutator")

    }



    // This mutator performs a complex pattern search and replacement,

    // so it overrides mutate directly instead of using BaseInstructionMutator.

    public override func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Program? {

        resetState()

        scan(program)



        // Check if the full pattern was found

        guard

            let oomIdx = oomInstructionIdx,

            let destructIdx = destructInstructionIdx,

            let createEmptyIdx = createEmptyArrayInstrIdx,

            let returnIdx = returnInstrIdx,

            let callIdx = iifeCallInstrIdx,

            let funcDefIdx = functionDefinitionInstrIdx,

            let funcEndIdx = functionEndInstrIdx,

            // Ensure the instructions are in a plausible order

            oomIdx < callIdx,

            callIdx < destructIdx,

            funcDefIdx < createEmptyIdx,

            createEmptyIdx < returnIdx,

            returnIdx < funcEndIdx

        else {

            // Required pattern not found or incomplete

            return nil

        }



        // Apply the transformation by rebuilding the program instruction by instruction

        b.adopting(program) { // Build the new program



            // Copy instructions before oomAtAllocation

            for i in 0..<oomIdx {

                b.adopt(program.code[i])

            }



            // Skip oomAtAllocation instruction (Effectively commenting it out)

            b.trace("Removing oomAtAllocation instruction at original index \(oomIdx)")





            // Copy instructions between oomAtAllocation and the IIFE Function Definition

            for i in (oomIdx + 1)..<funcDefIdx {

                 b.adopt(program.code[i])

            }



            // Rebuild the IIFE function

            let funcDefInstr = program.code[funcDefIdx]

            guard let beginOp = funcDefInstr.op as? BeginAnyFunction else {

                b.trace("Error: Expected BeginAnyFunction at funcDefIdx \(funcDefIdx). Aborting.")

                return // Abort block adoption

            }

            // The variable defined by BeginAnyFunction is reassigned inside the block by Fuzzilli's builder

            let functionVar = funcDefInstr.output

            let parameters = funcDefInstr.innerOutputs



            // Find the original output variable of the empty CreateArray

            guard program.code[createEmptyIdx].op is CreateArray else {

                 b.trace("Error: Expected CreateArray at createEmptyIdx \(createEmptyIdx). Aborting.")

                 return // Abort block adoption

            }

            let originalEmptyArrayVar = program.code[createEmptyIdx].output



            // Use b.block for rebuilding the function body correctly

            b.block(beginOp, parameters: parameters, reassigns: [functionVar]) {

                var replacementArrayVar: Variable? = nil



                // Iterate through the original function body indices (inside Begin/End block)

                for i in (funcDefIdx + 1)..<funcEndIdx {

                     let currentInstr = program.code[i]



                    if i == createEmptyIdx {

                        // Replace CreateArray([]) with LoadInteger(1) and CreateArray([1])

                         b.trace("Replacing CreateArray([]) with CreateArray([1]) inside IIFE")

                        let one = b.loadInt(1)

                        replacementArrayVar = b.createArray(with: [one], spreading: [false])

                        // Skip adopting the original CreateArray instruction.



                    } else if i == returnIdx {

                        // Adopt the return instruction, but modify its input if needed.

                        guard currentInstr.op is Return, currentInstr.numInputs == 1 else {

                            b.trace("Warning: Expected Return instruction with 1 input at returnIdx \(returnIdx). Adopting original.")

                            b.adopt(currentInstr) // Adopt original if unexpected

                            continue

                        }



                        var returnInput = currentInstr.input(0)

                        if returnInput == originalEmptyArrayVar, let newVar = replacementArrayVar {

                            b.trace("Updating Return instruction input from \(returnInput) to use new array var \(newVar)")

                            returnInput = newVar // Use the new array variable

                        } else if returnInput == originalEmptyArrayVar {

                             b.trace("Warning: Return used original empty array var \(originalEmptyArrayVar), but replacement var is missing. Returning undefined.")

                             // Fallback: return undefined as a safer default if the fix failed.

                             returnInput = b.loadUndefined()

                        } else {

                             b.trace("Return instruction input \(returnInput) did not match original empty array var \(originalEmptyArrayVar). Keeping original input.")

                             // Keep the original input if it wasn't the empty array var

                        }

                        b.doReturn(value: returnInput)

                        // Skip adopting the original Return instruction as we generated a new one.



                    } else { // Adopt other instructions within the function body

                         b.adopt(currentInstr)

                    }

                }

                 // The b.block handles the EndFunction implicitly.

            } // End of function rebuild block





            // Copy instructions between the end of the IIFE function definition and the call

            for i in (funcEndIdx + 1)..<callIdx {

                 b.adopt(program.code[i])

            }



            // Adopt the Call instruction, capturing its output into a new variable

            let originalCallInstr = program.code[callIdx]

            // Ensure it's a call operation before proceeding

            guard originalCallInstr.op.isCall else {

                b.trace("Error: Expected Call operation at callIdx \(callIdx). Aborting.")

                return // Abort block adoption

            }

            let callArguments = originalCallInstr.inputs // Includes function var + actual args

            let resultVar = b.nextVariable() // Variable for the intermediate result 'result'

            b.trace("Assigning IIFE call result to intermediate variable \(resultVar)")

            // Create a new Call instruction that outputs to resultVar

            b.adopt(Instruction(originalCallInstr.op, output: resultVar, inputs: callArguments))





            // Copy instructions between the call and the original destructuring

            for i in (callIdx + 1)..<destructIdx {

                b.adopt(program.code[i])

            }





            // Replace the old DestructArray instruction with a new one using the intermediate variable

            b.trace("Replacing DestructArray([]) with DestructArray([x]) using intermediate variable \(resultVar)")

            let destructuredVar = b.nextVariable() // The 'x' in let [x] = result

            // Perform 'let [x] = result'

            b.destructArray(resultVar, selecting: [0], hasRestElement: false, outputs: [destructuredVar])





            // Copy remaining instructions after the original destructuring

            for i in (destructIdx + 1)..<program.code.count {

                b.adopt(program.code[i])

            }

        } // End of adopting block



        // Finalize and return the mutated program

        return b.finalize()

    }





    private func resetState() {

        oomInstructionIdx = nil

        destructInstructionIdx = nil

        createEmptyArrayInstrIdx = nil

        returnInstrIdx = nil

        iifeCallInstrIdx = nil

        functionDefinitionInstrIdx = nil

        functionEndInstrIdx = nil

    }



    /// Scans the program to find the specific instruction pattern indices.

    private func scan(_ program: Program) {

        var destructInputVar: Variable? = nil

        var functionVar: Variable? = nil

        var foundOom = false

        var foundCall = false

        var foundDestruct = false

        var foundFuncDef = false

        var foundCreateEmpty = false

        var foundReturn = false



        // Iterate through the program to find potential candidates and their relative order

        for (idx, instr) in program.code.enumerated() {



            // Find oomAtAllocation

            if !foundOom, let op = instr.op as? Explore, op.action.lowercased().contains("oomatallocation") {

                oomInstructionIdx = idx

                foundOom = true

            }



            // Find the IIFE Call (must follow oom)

            // Check if this instruction's output is potentially used by a later DestructArray []

            // This is hard to check directly here, so we look for *any* CallFunction whose input function

            // is defined just before it (a common IIFE pattern).

            // A more robust check waits until DestructArray is found (see below).



            // Find the DestructArray [] pattern

            if !foundDestruct, let op = instr.op as? DestructArray, op.indices.isEmpty, !op.hasRestElement, instr.numOutputs == 0 {

                // Check if it comes after a potential OOM and Call

                if foundOom, oomInstructionIdx! < idx { // Check if OOM preceded this

                    destructInstructionIdx = idx

                    destructInputVar = instr.input(0)

                    foundDestruct = true

                     // Now that we have the target var, we can definitively find the call that defines it

                }

            }

        }



        // If we didn't find the destructuring pattern, stop.

        guard foundDestruct, let targetVar = destructInputVar else {

             resetState()

             return

        }



        // Pass 2: Find the *specific* call that defines the destructured variable and the function it calls.

        // Also re-verify OOM ordering.

        foundOom = false // Reset OOM flag for ordered check

        for (idx, instr) in program.code.enumerated() {

             // Re-confirm OOM location if needed

             if idx == oomInstructionIdx { foundOom = true }



             // Check if this instruction defines the target variable for destructuring

             if instr.output == targetVar {

                 // Is it a call instruction and does it follow OOM?

                 if instr.op.isCall, foundOom, idx > oomInstructionIdx!, idx < destructInstructionIdx! {

                    iifeCallInstrIdx = idx

                    foundCall = true

                    // The first input is usually the function being called

                    if instr.numInputs > 0 {

                        functionVar = instr.input(0)

                    }

                    break // Found the defining call in the correct order

                 } else {

                    // Found the definition, but order/type is wrong. Invalidate.

                    resetState()

                    return

                 }

             }

             // If we pass the destructure index without finding the call, something is wrong

             if idx >= destructInstructionIdx! {

                 resetState()

                 return

             }

        }



        // If we didn't find the call or the function variable, stop.

        guard foundCall, let funcVar = functionVar, let callIdx = iifeCallInstrIdx else {

            resetState()

            return

        }



        // Pass 3: Find the function definition block for funcVar that precedes the call.

        for (idx, instr) in program.code.enumerated() {

             // Stop searching if we reach the call instruction index

             if idx >= callIdx { break }



             if instr.output == funcVar, instr.op is BeginAnyFunction {

                if let endIdx = program.code.findBlockEnd(startIndex: idx) {

                    functionDefinitionInstrIdx = idx

                    functionEndInstrIdx = endIdx

                    foundFuncDef = true

                    break // Found the function definition block

                }

             }

        }



        // If we didn't find the function definition block, stop.

        guard foundFuncDef, let funcDefIdx = functionDefinitionInstrIdx, let funcEndIdx = functionEndInstrIdx else {

            resetState()

            return

        }



        // Pass 4: Scan *inside* the identified function body for CreateArray([]) followed by Return.

        var emptyArrayVar: Variable? = nil

        for idx in (funcDefIdx + 1)..<funcEndIdx {

             let instr = program.code[idx]



             // Look for CreateArray with no inputs, store its index and output var

             if !foundCreateEmpty, instr.op is CreateArray, instr.numInputs == 0 {

                createEmptyArrayInstrIdx = idx

                emptyArrayVar = instr.output

                foundCreateEmpty = true

             }



             // Look for Return instruction after finding CreateArray

             if foundCreateEmpty, instr.op is Return {

                 // Check if it returns the empty array we found just before

                 if let emptyVar = emptyArrayVar, instr.numInputs == 1, instr.input(0) == emptyVar, idx > createEmptyArrayInstrIdx! {

                     returnInstrIdx = idx

                     foundReturn = true

                     break // Found the full pattern inside the function

                 } else {

                     // Found a Return, but it doesn't return the expected empty array. Reset inner findings.

                     foundCreateEmpty = false

                     foundReturn = false

                     emptyArrayVar = nil

                     createEmptyArrayInstrIdx = nil

                     // Continue searching within the function in case there's another pattern

                 }

             }

        }



        // Final check: Ensure all parts were found and indices are valid.

        // Order checks were mostly done during the scan.

        if !(foundOom && foundCall && foundDestruct && foundFuncDef && foundCreateEmpty && foundReturn) {

            resetState() // Invalidate if any part is missing

        }

        // Additional sanity check on indices (should be guaranteed by scan logic if successful)

        guard oomInstructionIdx != nil, destructInstructionIdx != nil, iifeCallInstrIdx != nil,

              functionDefinitionInstrIdx != nil, createEmptyArrayInstrIdx != nil, returnInstrIdx != nil,

              functionEndInstrIdx != nil else {

            resetState()

            return

        }

    }

}
