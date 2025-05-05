

/// Mutator that specifically targets the IIFE update pattern in a for-loop

/// (where the loop variable is incremented/decremented inside an IIFE used

/// as the update expression) as seen in a SpiderMonkey JIT leak

/// (Bug 1874704, attachment 9379127).

/// It replaces this pattern with a standard unary increment/decrement operation

/// placed directly before the EndForLoop instruction.

public class FixIifeLoopUpdateMutator: BaseMutator {

    let logger = Logger(withLabel: "FixIifeLoopUpdateMutator")



    public init() {

        super.init(name: "FixIifeLoopUpdateMutator")

    }



    // Structure to hold information about the found pattern

    private struct PatternInfo {

        let funcDefStartIdx: Int

        let funcDefEndIdx: Int

        let callInstrIdx: Int

        let endLoopIdx: Int

        let loopVar: Variable

        let updateOp: UnaryOperation.Operator // The specific ++ or -- operation found inside the IIFE

    }



    override public func mutate(_ program: Program, using fuzzer: Fuzzer) -> Program? {

        var pattern: PatternInfo? = nil



        // --- First Pass: Find the specific pattern ---

        // The pattern looks for:

        // BeginForLoop(v)

        // ...

        // BeginPlainFunctionDefinition -> f

        //   ...

        //   UnaryOperation(++/--, v) // Must be the loop variable v

        //   ...

        // EndPlainFunctionDefinition(f)

        // CallFunction(f) // Must be immediately after EndPlainFunctionDefinition (potentially comments ignored)

        // EndForLoop(v) // Must be immediately after CallFunction (potentially comments ignored)



        var loopStack: [Variable] = [] // Track loop variables for nesting

        var potentialFuncDefStart: Int? = nil

        var potentialFuncVar: Variable? = nil

        var potentialUpdateOp: UnaryOperation.Operator? = nil

        var potentialCallIdx: Int? = nil

        var potentialFuncEndIdx: Int? = nil



        for (i, instr) in program.code.enumerated() {

            // Reset pattern tracking if we encounter an instruction that breaks the expected sequence

            // before the pattern is fully confirmed at EndForLoop.

            var resetPatternState = false

            if potentialFuncDefStart != nil && potentialFuncEndIdx == nil && !(instr.op is BeginPlainFunctionDefinition || instr.op is EndPlainFunctionDefinition || instr.op is UnaryOperation || instr.op is BeginCode || instr.op is EndCode || instr.op is Comment || instr.op is Nop || program.code.scopes(at: i).contains(potentialFuncDefStart!)) {

                 // If we started matching a function but are now outside it before finding EndPlainFunctionDefinition

                 resetPatternState = true

            }

            if potentialFuncEndIdx != nil && potentialCallIdx == nil && !(instr.op is CallFunction || instr.op is Comment || instr.op is Nop) {

                 // If we finished the function def but haven't seen the call yet, and see something else significant

                 resetPatternState = true

            }

             if potentialCallIdx != nil && !(instr.op is EndForLoop || instr.op is Comment || instr.op is Nop) {

                 // If we saw the call but haven't seen the EndForLoop yet, and see something else significant

                 resetPatternState = true

             }



            if resetPatternState {

                potentialFuncDefStart = nil

                potentialFuncVar = nil

                potentialUpdateOp = nil

                potentialCallIdx = nil

                potentialFuncEndIdx = nil

            }



            // Main state machine logic

            if instr.op is BeginForLoop {

                loopStack.append(instr.output)

                // Reset potential pattern state when entering a new loop

                potentialFuncDefStart = nil

                potentialFuncVar = nil

                potentialUpdateOp = nil

                potentialCallIdx = nil

                potentialFuncEndIdx = nil

            } else if instr.op is EndForLoop {

                if !loopStack.isEmpty && instr.numInputs > 0 && loopStack.last == instr.inputs[0] {

                    // Check if we just completed the pattern right before this EndForLoop

                    if let p_start = potentialFuncDefStart,

                       let p_end = potentialFuncEndIdx, // Make sure func end was found

                       let p_funcVar = potentialFuncVar, // Make sure func var was captured

                       let p_update = potentialUpdateOp, // Make sure update op was found

                       let p_call = potentialCallIdx, // Make sure call index was captured

                       // Verify the call instruction is correct

                       program.code[p_call].op is CallFunction,

                       program.code[p_call].inputs[0] == p_funcVar,

                       // Verify the EndForLoop matches the loop var potentially updated

                       instr.inputs[0] == loopStack.last!

                    {

                        // Found the fully structured pattern ending at index i

                        pattern = PatternInfo(

                            funcDefStartIdx: p_start,

                            funcDefEndIdx: p_end,

                            callInstrIdx: p_call,

                            endLoopIdx: i,

                            loopVar: loopStack.last!,

                            updateOp: p_update

                        )

                        // Found it, break the loop (only fix one occurrence)

                        break

                    }

                    // Pop loop regardless of whether pattern was found for this specific EndForLoop

                    loopStack.removeLast()

                    // Reset state after loop ends

                    potentialFuncDefStart = nil

                    potentialFuncVar = nil

                    potentialUpdateOp = nil

                    potentialCallIdx = nil

                    potentialFuncEndIdx = nil



                } else {

                     // Mismatched EndForLoop or unexpected state, clear stack and reset

                     if !loopStack.isEmpty { loopStack.removeLast() } // Try to recover by popping

                     potentialFuncDefStart = nil

                     potentialFuncVar = nil

                     potentialUpdateOp = nil

                     potentialCallIdx = nil

                     potentialFuncEndIdx = nil

                }

            } else if !loopStack.isEmpty {

                // Inside a loop, look for the pattern elements in sequence

                let currentLoopVar = loopStack.last!



                if potentialFuncDefStart == nil && instr.op is BeginPlainFunctionDefinition {

                    // Start of potential IIFE definition

                    potentialFuncDefStart = i

                    potentialFuncVar = instr.output

                    potentialUpdateOp = nil // Reset update op for new function

                    potentialCallIdx = nil

                    potentialFuncEndIdx = nil

                } else if let startIdx = potentialFuncDefStart, i > startIdx, let funcVar = potentialFuncVar {

                    // Looking inside or just after the potential function definition



                    // Check if inside the function definition scope

                    if potentialFuncEndIdx == nil {

                         if let op = instr.op as? UnaryOperation,

                            instr.inputs[0] == currentLoopVar,

                            (op.op == .PostInc || op.op == .PreInc || op.op == .PostDec || op.op == .PreDec) {

                             // Found the update operation inside the function body

                             potentialUpdateOp = op.op

                         } else if instr.op is EndPlainFunctionDefinition && instr.inputs.count > 0 && instr.inputs[0] == funcVar {

                              // Found the end of the function definition

                              potentialFuncEndIdx = i

                         }

                    } else {

                         // We are after the function definition end, look for the call

                         if potentialCallIdx == nil && instr.op is CallFunction && instr.inputs.count > 0 && instr.inputs[0] == funcVar && potentialUpdateOp != nil {

                              // Found the call, and we previously found the update op

                              potentialCallIdx = i

                         }

                    }

                }

            }

        } // End of first pass



        guard let pattern = pattern else {

            // Target IIFE loop update pattern not found or was malformed

            return nil

        }



        // --- Second Pass: Rebuild the program ---

        let b = fuzzer.makeBuilder()

        var mutated = false



        b.adopting(from: program) { instr, idx in

            if idx >= pattern.funcDefStartIdx && idx <= pattern.funcDefEndIdx {

                // Skip adopting the function definition instructions

                if idx == pattern.funcDefStartIdx {

                    b.trace("FixIifeLoopUpdate: Skipping IIFE definition [\(pattern.funcDefStartIdx)-\(pattern.funcDefEndIdx)]")

                    mutated = true

                }

                // Do not adopt these instructions

                return .continue

            } else if idx == pattern.callInstrIdx {

                // Skip adopting the call instruction itself

                b.trace("FixIifeLoopUpdate: Skipping IIFE call at \(idx)")

                mutated = true

                 // Do not adopt this instruction

                return .continue

            } else if idx == pattern.endLoopIdx {

                // BEFORE adopting the EndForLoop, insert the standard update operation

                // that was previously identified inside the IIFE.

                b.trace("FixIifeLoopUpdate: Inserting standard update \(pattern.updateOp) for \(pattern.loopVar) before EndForLoop")

                b.unary(pattern.updateOp, on: pattern.loopVar)



                // Now adopt the original EndForLoop instruction

                b.adopt(instr)

                return .continue

            } else {

                // Adopt all other instructions normally

                b.adopt(instr)

                return .continue

            }

        }



        // Note: This mutator does not attempt to add dummy operations into the potentially

        // emptied loop body, nor does it rename the surrounding function ('f' -> 'f_circumvent').

        // It focuses solely on replacing the IIFE update mechanism with a standard one.



        return mutated ? b.finalize() : nil

    }

}


