

// A mutator specifically designed to transform the positive test case

// (causing a Debugger assertion failure) into the negative test case (avoiding it).

// It comments out `removeDebuggee` within the debugger callback, ensures the

// debuggee function returns an iterable, and wraps the triggering loop in try-catch.

public class DebuggerCallbackFixMutator: BaseMutator {



    public init() {

        super.init(name: "DebuggerCallbackFixMutator")

    }



    // We operate on the whole program as context is needed.

    override public func mutate(_ program: Program, using b: ProgramBuilder, for FuzzingStat: FuzzingStatistics) -> Program? {



        var modified = false

        var newProg = Program()

        // Use a ProgramBuilder to construct the potentially modified program.

        let builder = ProgramBuilder(for: &newProg, copyingFrom: program)

        // builder.trace("Attempting to apply DebuggerCallbackFixMutator") // Optional tracing



        var debuggerCallbackFunctionVar: Variable? = nil

        var removeDebuggeeIndices = [Int]()

        var forOfBlocks = [(start: Int, end: Int)]()

        var evalInstructionsToModify = [(index: Int, output: Variable, originalString: String)]()



        // --- Pass 1: Identify potential modification sites ---



        // Find the assignment to onDebuggerStatement to identify the callback function variable.

        // This assumes the callback is assigned directly.

        for (idx, instr) in program.code.enumerated() {

            var assignedValueVar: Variable? = nil

            if instr.op is StoreProperty, (instr.op as! StoreProperty).propertyName == "onDebuggerStatement" {

                assignedValueVar = instr.input(1)

            } else if instr.op is SetProperty, (instr.op as! SetProperty).propertyName == "onDebuggerStatement" {

                 assignedValueVar = instr.input(1)

            } else if instr.op is StorePropertyComputed, (instr.op as! StorePropertyComputed).propertyName == "onDebuggerStatement" {

                 assignedValueVar = instr.input(2) // obj, propName, value

            } else if instr.op is SetPropertyComputed, (instr.op as! SetPropertyComputed).propertyName == "onDebuggerStatement" {

                 assignedValueVar = instr.input(2) // obj, propName, value

            }



            if let callbackVar = assignedValueVar {

                 // Basic check: Is the assigned value likely a function?

                 // A more robust check might involve tracking type information if available.

                 if program.code.contains(where: { $0.op is BeginAnyFunctionDefinition && $0.output == callbackVar }) {

                    debuggerCallbackFunctionVar = callbackVar

                    // builder.trace("Found potential debugger callback assignment at \(idx): \(instr) assigning \(callbackVar)")

                    break // Assume only one relevant assignment for simplicity

                 }

            }

        }



        // If we couldn't identify the callback function, we can't proceed reliably.

        guard let callbackFuncVar = debuggerCallbackFunctionVar else {

             // builder.trace("Could not find assignment of a function to onDebuggerStatement.")

             return nil

        }

        // builder.trace("Debugger callback function variable identified as \(callbackFuncVar)")



        // Find the definition block of the identified callback function.

        var callbackFuncDefStartIdx: Int? = nil

        var callbackFuncDefEndIdx: Int? = nil

        for (idx, instr) in program.code.enumerated() {

            // Check if this instruction starts the definition of our callback function.

            if instr.op is BeginAnyFunctionDefinition && instr.output == callbackFuncVar {

                callbackFuncDefStartIdx = idx

                // builder.trace("Found definition start for \(callbackFuncVar) at \(idx)")

                // Scan forward to find the matching EndAnyFunctionDefinition.

                var depth = 0

                for i in idx..<program.code.count {

                     let currentOp = program.code[i].op

                     if currentOp is BeginAnyFunctionDefinition { depth += 1 }

                     else if currentOp is EndAnyFunctionDefinition {

                         depth -= 1

                         if depth == 0 {

                             callbackFuncDefEndIdx = i

                             // builder.trace("Found definition end for \(callbackFuncVar) at \(i)")

                             break

                         }

                     }

                 }

                 break // Found the function definition block.

            }

        }



        // If we didn't find the full definition block, abort.

        guard let startIdx = callbackFuncDefStartIdx, let endIdx = callbackFuncDefEndIdx else {

             // builder.trace("Could not find definition block for \(callbackFuncVar)")

            return nil

        }



        // Search for 'removeDebuggee' method calls *only* within the callback function body.

        for idx in (startIdx + 1)..<endIdx {

            let instr = program.code[idx]

            if instr.op is CallMethod, (instr.op as! CallMethod).methodName == "removeDebuggee" {

                removeDebuggeeIndices.append(idx)

                // builder.trace("Found removeDebuggee call inside callback at \(idx)")

            }

        }



        // If the specific transformation requires removing this call, and it's not found, abort.

        if removeDebuggeeIndices.isEmpty {

             // builder.trace("Did not find removeDebuggee call inside the identified callback function.")

             return nil

        }





        // Find top-level for...of loops anywhere in the program.

        var forOfDepth = 0

        var currentForOfStart: Int? = nil

        for (idx, instr) in program.code.enumerated() {

            if instr.op is BeginForOf {

                if forOfDepth == 0 {

                   currentForOfStart = idx

                }

                forOfDepth += 1

            } else if instr.op is EndForOf {

                 if forOfDepth > 0 { // Match Begin/End pairs

                    forOfDepth -= 1

                    if forOfDepth == 0, let start = currentForOfStart {

                       forOfBlocks.append((start: start, end: idx))

                       currentForOfStart = nil

                       // builder.trace("Found for...of block from \(start) to \(idx)")

                    }

                 }

            }

        }

        // This basic finding assumes non-nested loops need wrapping. A more complex logic

        // could identify the specific loop calling the function that triggers the debugger.



         if forOfBlocks.isEmpty {

              // builder.trace("Did not find any for...of loops to wrap.")

              // If the target transformation requires wrapping a loop, abort if none found.

              return nil

         }



        // Find LoadString instructions used in an 'eval' call containing 'debugger;'

        // and likely missing a 'return'.

         for (idx, instr) in program.code.enumerated() {

             if instr.op is LoadString,

                let stringVal = (instr.op as! LoadString).value,

                stringVal.contains("debugger;"), // Contains the keyword

                // Heuristic: Check if it likely lacks a return statement after debugger

                // This could be fooled by comments or complex code.

                !stringVal.contains("return"),

                // Check if the next instruction is a CallMethod 'eval' using this string

                idx + 1 < program.code.count,

                let callInstr = program.code[idx + 1].op as? CallMethod,

                callInstr.methodName == "eval",

                program.code[idx + 1].numInputs > 1, // obj, string, ...

                program.code[idx + 1].input(1) == instr.output // Check if the string is the argument

             {

                 evalInstructionsToModify.append((index: idx, output: instr.output, originalString: stringVal))

                 // builder.trace("Found potentially problematic eval string at \(idx)")

             }

         }



         // If the target requires modifying an eval string, abort if none suitable is found.

         if evalInstructionsToModify.isEmpty {

              // builder.trace("Did not find eval string needing modification.")

              return nil

         }





        // --- Pass 2: Build the new program with modifications ---

        // Use Sets for efficient lookup of indices that need special handling.

        let removeIndicesSet = Set(removeDebuggeeIndices)

        let forOfStarts = Set(forOfBlocks.map { $0.start })

        let forOfEnds = Set(forOfBlocks.map { $0.end })

        let evalIndicesToModifySet = Set(evalInstructionsToModify.map { $0.index })



        // Iterate through the original program and append instructions to the builder,

        // applying modifications where needed.

        for (idx, instr) in program.code.enumerated() {



            // Action 1: Skip 'removeDebuggee' calls identified within the callback.

            if removeIndicesSet.contains(idx) {

                modified = true

                // builder.trace("Skipping instruction \(idx): \(instr)")

                continue // Do not append this instruction to the new program.

            }



            // Action 2: Modify 'LoadString' for 'eval' if identified.

            if evalIndicesToModifySet.contains(idx) {

                // Retrieve the details needed for modification.

                guard let modificationInfo = evalInstructionsToModify.first(where: { $0.index == idx }) else {

                    // Should not happen due to Set containment check, but defensively copy.

                    builder.adopt(instr)

                    continue

                }

                let originalString = modificationInfo.originalString

                // Perform the specific string replacement.

                // WARNING: This is a simple string replacement and might break complex JS code.

                let newString = originalString.replacingOccurrences(of: "debugger;", with: "debugger; return [];", options: [], range: nil)



                if newString != originalString {

                    // If the string changed, append a new LoadString instruction.

                    builder.append(Instruction(LoadString(value: newString), output: modificationInfo.output))

                    modified = true

                    // builder.trace("Modifed eval string at \(idx)")

                } else {

                     // If string didn't change (e.g., already had return), copy original.

                     builder.adopt(instr)

                }

                continue // Skip the generic adopt step below.

            }





            // Action 3: Wrap identified for...of loops in try...catch.

            // If this instruction is the start of a loop to wrap, prepend BeginTry.

            if forOfStarts.contains(idx) {

                builder.beginTry()

                // builder.trace("Added BeginTry before for...of at \(idx)")

                // The current instruction (BeginForOf) will be appended next.

            }



            // Append the current instruction (either original or after BeginTry).

            builder.adopt(instr)



            // If this instruction is the end of a loop to wrap, append the catch block.

            if forOfEnds.contains(idx) {

                builder.beginCatch()

                // We add an empty catch block, sufficient for preventing the crash.

                // builder.trace("Added BeginCatch/EndTryCatch after for...of at \(idx)")

                builder.endTryCatch()

                // Wrapping the loop counts as a modification.

                // We set modified=true when BeginTry is added or removeDebuggee skipped etc.

                // Setting it here ensures modification is flagged even if only wrapping occurs.

                modified = true

            }

        }



        // --- Finalize ---

        // Only return the new program if we actually made one of the intended changes.

        if modified {

             // builder.trace("Mutation successful.")

            builder.finalize() // Finalize the constructed program.

            return newProg

        } else {

             // builder.trace("Mutation conditions not fully met or no changes applied.")

            // If no modifications were made, return nil to indicate failure.

            return nil

        }

    }

}
