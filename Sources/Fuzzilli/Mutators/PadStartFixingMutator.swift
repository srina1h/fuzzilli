

public class PadStartFixingMutator: Mutator {

    public init() {

        super.init(name: "PadStartFixingMutator")

    }



    public override func mutate(_ program: Program, for fuzzer: Fuzzer) -> Program? {

        let b = fuzzer.makeBuilder()

        var mutated = false



        b.adopting(from: program) {

            var targetPadStartIndices = [Int]()

            var targetForLoopVar: Variable? = nil

            var targetForLoopStart = -1

            var targetForOfLoopStart = -1

            var targetForOfLoopVar: Variable? = nil

            var fixedLengthVar: Variable? = nil



            findPatterns: for (idx, instr) in program.code.enumerated() {

                if instr.op is CallMethod,

                   let op = instr.op as? CallMethod,

                   op.methodName == "padStart",

                   instr.numInputs >= 2 {

                    let lengthVar = instr.input(1)

                    var definingLoopIdx = -1

                    var loopVarCandidate: Variable? = nil

                    for i in stride(from: idx - 1, through: 0, by: -1) {

                        let candidateInstr = program.code[i]

                        if candidateInstr.op is BeginForLoop, candidateInstr.numOutputs == 2 {

                            let loopVar2 = candidateInstr.output(1)

                            if loopVar2 == lengthVar {

                                definingLoopIdx = i

                                loopVarCandidate = loopVar2

                                break

                            }

                        }

                        // Basic block end check to avoid searching too far back unwisely

                        if candidateInstr.isBlockEnd {

                           break

                        }

                    }



                    if let foundLoopVar = loopVarCandidate, definingLoopIdx != -1 {

                        targetPadStartIndices.append(idx)

                        targetForLoopVar = foundLoopVar

                        targetForLoopStart = definingLoopIdx

                    }

                }



                if instr.op is BeginForOfLoop,

                   idx + 1 < program.code.count,

                   program.code[idx + 1].op is EndForOfLoop,

                   program.code[idx + 1].beginMarker == instr {

                    targetForOfLoopStart = idx

                    targetForOfLoopVar = instr.output

                }

            }



            guard !targetPadStartIndices.isEmpty,

                  let loopVarToReplace = targetForLoopVar,

                  targetForLoopStart != -1,

                  targetForOfLoopStart != -1,

                  let forOfVar = targetForOfLoopVar else {

                return

            }





            var processedPadStartIndices = Set<Int>()

            var processedForOfLoop = false



            for (idx, instr) in program.code.enumerated() {

                if idx == targetForLoopStart && fixedLengthVar == nil {

                    fixedLengthVar = b.loadInt(10)

                }



                if targetPadStartIndices.contains(idx), let constVar = fixedLengthVar {

                    var newInouts = instr.inouts

                    if newInouts.count > 1 && newInouts[1] == loopVarToReplace {

                        newInouts[1] = constVar

                        b.append(Instruction(instr.op, inouts: newInouts, flags: instr.flags))

                        processedPadStartIndices.insert(idx)

                        mutated = true

                    } else {

                        b.append(instr)

                    }

                } else if idx == targetForOfLoopStart && !processedForOfLoop {

                     b.append(instr)

                     let lengthProp = b.getProperty(forOfVar, "length")

                     let tempVar = b.loadUndefined()

                     b.reassign(tempVar, lengthProp)

                     mutated = true // Consider adding the body as a mutation

                } else if idx == targetForOfLoopStart + 1,

                          program.code[idx].op is EndForOfLoop,

                          let beginInstr = program.code[idx].beginMarker,

                          beginInstr == program.code[targetForOfLoopStart], // Ensure End matches the correct Begin

                          !processedForOfLoop {

                     b.append(instr)

                     processedForOfLoop = true

                } else if targetPadStartIndices.contains(idx) && fixedLengthVar == nil {

                     // Should not happen if logic is correct, but safety fallback

                     b.append(instr)

                } else {

                    b.append(instr)

                }

            }



            // Ensure the main parts were processed as expected for this specific transformation

            if fixedLengthVar == nil || processedPadStartIndices.count != targetPadStartIndices.count || !processedForOfLoop {

                 mutated = false // Abort if the transformation wasn't fully applied

            }

        }



        return mutated ? b.finalize() : nil

    }

}
