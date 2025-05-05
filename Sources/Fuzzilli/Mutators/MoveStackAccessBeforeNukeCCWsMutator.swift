

/// A mutator that specifically targets a pattern causing a crash in SpiderMonkey related to

/// accessing an error's stack property after `nukeAllCCWs()` invalidates necessary structures.

/// It attempts to move the `error.stack` access to *inside* the catch block, before `nukeAllCCWs()` is called.

///

/// Identifies the pattern:

/// ```fuzzil

/// ...

/// v1 = BeginTry()

///     ... // Code that might throw

/// v2 = BeginCatch() // Implicitly catches error into a conceptual var, let's say associated with v2 or defined right after

///     v3 = SomeOperation ... // Error object might be assigned to v3 here

/// EndTryCatch() // Ends at index E

/// ...

/// CallFunction 'nukeAllCCWs' // At index N > E

/// ...

/// LoadProperty 'stack' v3 // Problematic access at index P > N

/// ...

/// ```

/// Transforms it into:

/// ```fuzzil

/// ...

/// v1 = BeginTry()

///     ...

/// v2 = BeginCatch()

///     v3 = SomeOperation ...

///     v4 = LoadProperty 'stack' v3 // Access moved here

/// EndTryCatch()

/// ...

/// CallFunction 'nukeAllCCWs'

/// ...

/// // Original LoadProperty 'stack' v3 is removed/skipped

/// // Optionally, add usage of v4, e.g., v5 = LoadProperty 'length' v4; CallFunction 'print' v5

/// ...

/// ```

public class MoveStackAccessBeforeNukeCCWsMutator: BaseMutator {

    init() {

        super.init(name: "MoveStackAccessBeforeNukeCCWsMutator")

    }



    override public func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Program? {

        var targetInstrIndex: Int? = nil

        var errorVar: Variable? = nil

        var nukeCallIndex: Int? = nil

        var definitionIndex: Int? = nil

        var catchBeginIndex: Int? = nil

        var catchEndIndex: Int? = nil



        // Iterate through the program to find the specific problematic pattern

        for (idx, instr) in program.code.enumerated() {

            // Step 1: Find a potential problematic instruction: LoadProperty 'stack'

            guard instr.op is LoadProperty && instr.op.attributes.contains(.propertyName("stack")) else { continue }



            let potentialErrorVar = instr.input(0)



            // Step 2: Find where the input variable (potentialErrorVar) was defined

            guard let defIdx = program.findDefiningInstruction(of: potentialErrorVar) else { continue }



            // Step 3: Check if the definition occurred within a catch block

            // We trace backwards from the definition index to find a BeginCatch in the same or outer scope,

            // and then find its corresponding EndTryCatch.

            var currentIdx = defIdx

            var foundBeginCatch = false

            var beginCatchIdx = -1

            var endCatchIdx = -1

            while currentIdx >= 0 {

                 let currentInstr = program.code[currentIdx]

                 // Found the start of a catch block...

                 if currentInstr.op is BeginCatch {

                     // ...now find its end.

                     if let endIdx = program.findNextInstruction(startingAt: currentIdx, where: { $0.op is EndTryCatch }) {

                        // Verify that the definition index falls within this catch block's boundaries.

                        if defIdx > currentIdx && defIdx < endIdx {

                            foundBeginCatch = true

                            beginCatchIdx = currentIdx

                            endCatchIdx = endIdx

                            break // Found the relevant catch block

                        }

                     }

                 }

                 // If we hit the start of an unrelated block, stop searching upwards in this scope.

                 if currentInstr.isBlockBegin && !(currentInstr.op is BeginCatch) { break }

                 currentIdx -= 1 // Continue searching backwards

            }

            // If the definition was not found inside a catch block, this isn't the pattern.

            guard foundBeginCatch else { continue }



            // Step 4: Find a 'nukeAllCCWs' function call *after* the catch block ends, but *before* the LoadProperty 'stack'.

            var foundNukeCall = false

            var nukeIdx = -1

            for i in (endCatchIdx + 1)..<idx { // Search between EndTryCatch and LoadProperty

                let interveningInstr = program.code[i]

                // Heuristic: identify the call by its function name attribute.

                if interveningInstr.op is CallFunction,

                   interveningInstr.op.attributes.contains(.functionName("nukeAllCCWs"))

                {

                    foundNukeCall = true

                    nukeIdx = i

                    break // Found the relevant call

                }

            }

            // If the nukeAllCCWs call wasn't found in the critical region, this isn't the pattern.

            guard foundNukeCall else { continue }



            // Step 5: Pattern confirmed. Store the relevant indices and variables.

            targetInstrIndex = idx

            errorVar = potentialErrorVar

            nukeCallIndex = nukeIdx

            definitionIndex = defIdx

            catchBeginIndex = beginCatchIdx

            catchEndIndex = endCatchIdx

            break // Stop searching the program, we found our target pattern.

        }



        // If the complete pattern was not found, the mutator cannot apply.

        guard let targetIdx = targetInstrIndex,

              let errVar = errorVar,

              let defIdx = definitionIndex,

              nukeCallIndex != nil,

              catchBeginIndex != nil,

              catchEndIndex != nil

        else {

            return nil

        }



        // Step 6: Build the new program using ProgramBuilder, applying the transformation.

        var stackTraceVar: Variable? = nil // To store the result of the early stack access



        for i in 0..<program.size {

            let instr = program.code[i]



            // If this is the original problematic LoadProperty instruction, skip it.

            if i == targetIdx {

                continue

            }



            // Copy the current instruction into the builder, adopting variables.

            let remappedInputs = instr.inputs.map { b.adopt($0) }

            var remappedOutputs = instr.outputs.map { b.adopt($0) }

             // Handle inner outputs for block instructions correctly.

             if instr.hasInnerOutputs {

                  remappedOutputs.append(contentsOf: instr.innerOutputs.map { b.adopt($0) } )

             }

            b.append(Instruction(instr.op, inputs: remappedInputs, outputs: remappedOutputs, attributes: instr.attributes))



            // If we just copied the instruction that defines the error variable...

            if i == defIdx {

                // ...insert the LoadProperty 'stack' instruction immediately after it.

                let adoptedErrorVar = b.adopt(errVar) // Ensure the variable is valid in the builder's context.

                stackTraceVar = b.loadProperty("stack", of: adoptedErrorVar)

            }

        }



        // Step 7: Optionally, add some usage of the newly created stackTraceVar at the end.

        // This helps prevent optimizations from removing the variable as dead code.

        if let stVar = stackTraceVar {

            let adoptedSTVar = b.adopt(stVar) // Adopt if used again.

            // Example usage: load the 'length' property (common for strings/arrays).

            let length = b.loadProperty("length", of: adoptedSTVar)

            // Example usage: print the length. Assumes a 'print' function is available.

            b.callFunction("print", withArgs: [length])

        }



        // Final check: Ensure the mutation actually changed the program.

        guard b.numInstructions > 0 && (b.numInstructions != program.size || stackTraceVar != nil) else {

            // If the program is identical or empty, return nil.

            return nil

        }



        // Return the finalized, mutated program.

        return b.finalize()

    }

}


