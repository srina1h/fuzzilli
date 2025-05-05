

/// A mutator that identifies a pattern of repetitive string concatenation within a loop

/// followed by a potentially problematic usage (like `dumpValue` causing stack overflow

/// due to deep string ropes) and replaces it with an equivalent pattern using

/// Array.push inside the loop and Array.join afterwards.

///

/// This specifically transforms code like:

/// ```javascript

/// let v0 = "s";

/// for (let i = 0; i < N; ++i) {

///   v0 += "a\n"; // Creates deep rope structure

/// }

/// this.dumpValue(v0); // Crashes

/// ```

/// Into:

/// ```javascript

/// let parts = ["s"];

/// for (let i = 0; i < N; ++i) {

///   parts.push("a\n");

/// }

/// let v0 = parts.join(''); // Creates flat string

/// this.dumpValue(v0); // Should not crash

/// ```

public class StringConcatLoopToArrayJoinMutator: BaseMutator {

    private let logger = Logger(withLabel: "StringConcatLoopToArrayJoinMutator")



    public init() {

        super.init(name: "StringConcatLoopToArrayJoinMutator")

    }



    override public func mutate(_ program: Program, using b: ProgramBuilder) -> Bool {

        var candidates: [(loadStringIdx: Int, beginForIdx: Int, reassignIdx: Int, endForIdx: Int, usageIdx: Int, stringVar: Variable, initialString: String, addedStringVar: Variable, addedString: String)] = []



        // Find all potential patterns in the program

        for i in 0..<program.size {

            // Pattern Start: LoadString -> stringVar

            guard let instr1 = program.instructions[safe: i], instr1.op is LoadString else { continue }

            let op1 = instr1.op as! LoadString

            let stringVar = instr1.output

            let initialString = op1.value



            // Must be followed by: BeginFor

            guard let instr2 = program.instructions[safe: i+1], instr2.op is BeginFor else { continue }

            let beginForIdx = i + 1



            // Scan within the loop block for the specific reassignment pattern and the end

            var foundReassign = false

            var reassignIdx = -1

            var endForIdx = -1

            var addedStringVar: Variable? = nil

            var addedString: String? = nil

            var binaryOpInstrIdx = -1 // Index of the BinaryOperation

            var loadAddedStringInstrIdx = -1 // Index of the LoadString for the added part



            var currentNestingLevel = 0

            var loopBodyInstructions: [Int] = []



            for j in (beginForIdx)..<program.size {

                let currentInstr = program.instructions[j]



                if currentInstr.op is EndFor {

                    if currentNestingLevel == 0 {

                        // This EndFor matches our BeginFor

                        endForIdx = j

                        break

                    } else {

                        currentNestingLevel -= 1

                    }

                }



                // Store instruction indices within the target loop level

                if currentNestingLevel == 1 {

                    loopBodyInstructions.append(j)

                }



                if currentInstr.op is BeginFor {

                    currentNestingLevel += 1

                }

            }



            // Did we find a matching EndFor?

            guard endForIdx != -1 else { continue }



            // Analyze instructions within the identified loop body

            for idxInBody in loopBodyInstructions {

                let loopInstr = program.instructions[idxInBody]



                // Look for: Reassign stringVar, op=BinaryOperation(.Add, stringVar, addedStringVar), LoadString -> addedStringVar

                if loopInstr.op is Reassign && loopInstr.output == stringVar {

                    // Check the input source instruction (must be BinaryOperation)

                    guard let binaryOpInputVar = loopInstr.inputs.first, // Input to Reassign

                          let binaryOpInstr = program.definition(of: binaryOpInputVar),

                          let foundBinaryOpIdx = program.indexOf(binaryOpInputVar), // Find where BinaryOp result is defined

                          binaryOpInstr.op is BinaryOperation,

                          let binaryOp = binaryOpInstr.op as? BinaryOperation,

                          binaryOp.op == .Add,

                          binaryOpInstr.input(0) == stringVar else { continue } // Not the v = v + ... pattern



                    // Check the second input to BinaryOperation (must come from LoadString)

                    let potentialAddedStringVar = binaryOpInstr.input(1)

                    guard let loadAddedStringInstr = program.definition(of: potentialAddedStringVar),

                          let foundLoadAddedStringIdx = program.indexOf(potentialAddedStringVar),

                          loadAddedStringInstr.op is LoadString,

                          let loadAddedStringOp = loadAddedStringInstr.op as? LoadString else { continue } // Not adding a literal string



                    // Found the full reassignment pattern!

                    addedStringVar = potentialAddedStringVar

                    addedString = loadAddedStringOp.value

                    reassignIdx = idxInBody // Index of the Reassign instruction

                    binaryOpInstrIdx = foundBinaryOpIdx

                    loadAddedStringInstrIdx = foundLoadAddedStringIdx

                    foundReassign = true

                    break // Found the pattern within this loop, stop searching the body

                }

            }



            // Check if the specific reassignment pattern was found inside the loop

            guard foundReassign, let av = addedStringVar, let as_ = addedString else { continue }



            // Search for a usage of stringVar shortly after the loop

            var usageIdx = -1

            // Look a limited distance after the loop end

            for k in (endForIdx + 1)..<min(endForIdx + 10, program.size) {

                let instr = program.instructions[k]

                // Check if this instruction uses the target stringVar as an input

                if instr.inputs.contains(stringVar) {

                    // Basic heuristic: assume the first usage after the loop is the relevant one.

                    // Could be refined to check for specific calls like dumpValue if needed.

                    usageIdx = k

                    break

                }

            }



            // If usage is found, add this candidate

            if usageIdx != -1 {

                candidates.append((loadStringIdx: i, beginForIdx: beginForIdx, reassignIdx: reassignIdx, endForIdx: endForIdx, usageIdx: usageIdx, stringVar: stringVar, initialString: initialString, addedStringVar: av, addedString: as_))

                // Consider breaking here if only the first match is desired

                // break

            }

        }



        guard !candidates.isEmpty else {

            // logger.debug("StringConcatLoopToArrayJoinMutator: No suitable pattern found")

            return false // No matching pattern found

        }



        // Choose one candidate to mutate (e.g., the first one found)

        // Could potentially pick randomly: let target = candidates.randomElement()!

        let target = candidates[0]

        // logger.debug("StringConcatLoopToArrayJoinMutator: Attempting transformation for stringVar \(target.stringVar) defined at [\(target.loadStringIdx)]")



        // --- Perform the mutation using the builder ---



        // 1. Copy instructions before the initial LoadString

        b.adopting(from: program, upTo: target.loadStringIdx)



        // 2. Create array: let parts = [initialString];

        let partsVar = b.createVariable(ofType: .object()) // Array is an object

        let vInitialString = b.loadString(target.initialString)

        b.createArray(with: [vInitialString], creating: partsVar)



        // 3. Copy instructions between initial LoadString and BeginFor

        b.adopting(from: program, between: target.loadStringIdx + 1, and: target.beginForIdx)



        // 4. Adopt BeginFor

        b.adopt(program.instructions[target.beginForIdx])



        // 5. Find the index of the BinaryOperation instruction that performs the addition

        guard let binaryOpInstrIdx = program.indexOf(program.instructions[target.reassignIdx].input(0)) else {

             logger.error("Internal error: Could not find index of BinaryOperation feeding Reassign at \(target.reassignIdx)")

             return false

        }



        // 6. Copy instructions inside the loop *before* the BinaryOperation

        b.adopting(from: program, between: target.beginForIdx + 1, and: binaryOpInstrIdx)



        // 7. Add: parts.push(addedStringVar)

        // We use the variable that held the result of LoadString for the added part.

        b.callMethod("push", on: partsVar, withArgs: [target.addedStringVar])



        // 8. Copy instructions inside the loop *after* the Reassign instruction until EndFor

        b.adopting(from: program, between: target.reassignIdx + 1, and: target.endForIdx)



        // 9. Adopt EndFor

        b.adopt(program.instructions[target.endForIdx])



        // 10. Copy instructions between EndFor and the usage instruction

        b.adopting(from: program, between: target.endForIdx + 1, and: target.usageIdx)



        // 11. Add: let stringVar = parts.join('');

        let vEmptyString = b.loadString("")

        // Reuse the original stringVar variable for the output of join.

        // This ensures subsequent code using stringVar still works.

        b.callMethod("join", on: partsVar, withArgs: [vEmptyString], assigningTo: target.stringVar)



        // 12. Adopt the usage instruction (it should still work as stringVar is reassigned above)

        b.adopt(program.instructions[target.usageIdx])



        // 13. Adopt the rest of the program

        b.adopting(from: program, after: target.usageIdx)



        // logger.debug("StringConcatLoopToArrayJoinMutator: Transformation successful")

        return true // Mutation successful

    }

}
