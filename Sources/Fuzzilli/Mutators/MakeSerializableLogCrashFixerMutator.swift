

// Mutator specifically designed to transform the positive test case

// (makeSerializable().log crash) into the negative test case by removing

// the .log property access and adding code after the oomTest call.

public class MakeSerializableLogCrashFixerMutator: Fuzzilli.Mutator {



    public init() {

        super.init(name: "MakeSerializableLogCrashFixerMutator")

    }



    // This mutator performs a specific transformation across multiple instructions,

    // so we implement the main mutate function directly instead of using BaseInstructionMutator.

    public override func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> MutationResult {

        b.adopting(program: program) // Start building based on the input program



        var getPropertyLogIndex: Int? = nil

        var oomTestCallInstrIndex: Int? = nil // Index of the oomTest(..., function(){...}) call



        // Find the specific pattern: GetProperty "log" immediately following a CallFunction

        // whose input function is loaded via LoadBuiltin "makeSerializable", and locate

        // the surrounding oomTest call.

        for (i, instr) in b.code.enumerated() {

            // Check if it's GetProperty "log"

            if instr.op is GetProperty && instr.op.descriptor.properties == ["propertyName": "log"] {

                // Check the preceding instruction

                guard i > 0 else { continue }

                let prevInstr = b.code[i-1]



                // Check if prevInstr is CallFunction using output for GetProperty

                if prevInstr.op is CallFunction &&

                   prevInstr.hasOutput && instr.input(0) == prevInstr.output {



                    // Check if the function called was 'makeSerializable'

                    if let functionVar = prevInstr.input(0),

                       let loadInstr = b.definition(of: functionVar),

                       loadInstr.op is LoadBuiltin,

                       loadInstr.op.descriptor.properties == ["builtinName": "makeSerializable"] {



                        // Found the makeSerializable().log pattern.

                        getPropertyLogIndex = i



                        // Now, attempt to find the CallFunctionWithScope for oomTest

                        // that likely invoked the function containing this pattern.

                        // This involves finding the function definition boundaries and then the call site.



                        // 1. Find the start of the containing function definition

                        var depth = 0

                        var beginFuncInstrIndex: Int? = nil

                        for j in stride(from: i - 1, through: 0, by: -1) {

                            if b.code[j].isBlockEnd { depth += 1 }

                            if b.code[j].isBlockBegin {

                                if depth == 0 {

                                    // Found the start of the immediate block

                                    if b.code[j].op is BeginAnyFunctionDefinition {

                                        beginFuncInstrIndex = j

                                        break

                                    } else {

                                        // The pattern is not directly inside a function definition start? Abort.

                                        getPropertyLogIndex = nil // Reset pattern match

                                        break

                                    }

                                } else {

                                    depth -= 1

                                }

                            }

                        }

                        guard let beginIdx = beginFuncInstrIndex else {

                             getPropertyLogIndex = nil; continue // Could not find function boundary, continue search

                        }



                        // 2. Find the end of the function definition block

                         let functionDefinitionInstruction = b.code[beginIdx]

                         guard let endIdx = b.findEndOfBlock(startingAt: beginIdx) else {

                             getPropertyLogIndex = nil; continue // Malformed block?

                         }



                        // 3. Search *after* the function definition for the CallFunctionWithScope instruction

                        //    that calls this function AND uses the 'oomTest' builtin.

                        let funcSignature = (functionDefinitionInstruction.op as! BeginAnyFunctionDefinition).signature

                        for k in (endIdx + 1)..<b.code.count {

                            let currentInstr = b.code[k]

                            // Check if it's a call using the identified function signature

                            if let callOp = currentInstr.op as? CallFunctionWithScope, callOp.signature == funcSignature {

                                // Check if the function being called is 'oomTest'

                                if let oomTestVar = currentInstr.input(0),

                                   let loadOomTest = b.definition(of: oomTestVar),

                                   loadOomTest.op is LoadBuiltin,

                                   loadOomTest.op.descriptor.properties == ["builtinName": "oomTest"] {

                                    // Found the oomTest call site!

                                    oomTestCallInstrIndex = k

                                    break // Found the full pattern

                                }

                            }

                             // Consider simple CallFunction too, although CallFunctionWithScope is typical for oomTest callbacks

                             else if let callOp = currentInstr.op as? CallFunction, currentInstr.numInputs > 1 {

                                 // Heuristic: Check if first input is oomTest and another input uses the function definition's output (closure object)

                                 // This part is less precise and depends on how Fuzzilli represents closures passed to CallFunction.

                                 // We prioritize CallFunctionWithScope as it's more explicit.

                             }

                        }



                        // If we found the full pattern break the main search loop

                        if oomTestCallInstrIndex != nil {

                            break

                        } else {

                             // Reset if we found the property access but not the call site

                             getPropertyLogIndex = nil

                        }

                    } // end check makeSerializable

                } // end check CallFunction -> GetProperty

            } // end check GetProperty log

        } // end loop through instructions





        // Proceed with mutation only if the complete pattern was identified

        guard let idxToRemove = getPropertyLogIndex,

              let oomCallIdx = oomTestCallInstrIndex

        else {

            return .rejected // Specific pattern not found in the program

        }



        // Rebuild the program: Remove the GetProperty instruction and add code after oomTest call.

        let originalCode = b.code

        b.reset() // Clear the builder to reconstruct the program



        var insertedExtraCode = false

        for i in 0..<originalCode.count {

            if i == idxToRemove {

                b.trace("Removing GetProperty 'log' instruction at index \(i)")

                continue // Skip the GetProperty instruction

            }



            // Append the original instruction

            b.append(originalCode[i])



            // Check if we just appended the oomTest call instruction

            if i == oomCallIdx {

                b.trace("Adding drainJobQueue check and 'success' string after oomTest call at index \(i)")



                // Add: if (typeof drainJobQueue === "function") drainJobQueue();

                // Check if the environment supports the 'drainJobQueue' builtin

                if fuzzer.environment.hasBuiltin("drainJobQueue") {

                    let drainJobQueue = b.loadBuiltin("drainJobQueue")

                    let typeOfDrain = b.typeOf(drainJobQueue)

                    let functionString = b.loadString("function")

                    let condition = b.compare(typeOfDrain, functionString, .equal)

                    b.beginIf(condition)

                    b.callFunction(drainJobQueue, withArgs: [])

                    b.endIf()

                }



                // Add: "success";

                b.loadString("success")

                insertedExtraCode = true

            }

        }



        // Fallback: If oomTest call was the very last instruction (unlikely but possible)

        // add the code at the absolute end.

        if !insertedExtraCode && originalCode.count > 0 && originalCode.count - 1 == oomCallIdx {

             b.trace("Adding drainJobQueue check and 'success' string at the end of the program")

             if fuzzer.environment.hasBuiltin("drainJobQueue") {

                 let drainJobQueue = b.loadBuiltin("drainJobQueue")

                 let typeOfDrain = b.typeOf(drainJobQueue)

                 let functionString = b.loadString("function")

                 let condition = b.compare(typeOfDrain, functionString, .equal)

                 b.beginIf(condition)

                 b.callFunction(drainJobQueue, withArgs: [])

                 b.endIf()

             }

             b.loadString("success")

        }



        // Finalize the mutated program

        return .success(b.finalize())

    }

}
