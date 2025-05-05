

// A mutator that identifies instructions creating cyclic object references

// (e.g., obj.prop = obj or obj[prop] = obj) and replaces the self-assignment

// with an assignment to `null`. This aims to prevent stack overflows

// in recursive operations on such objects, like the one observed in

// Debugger().memory.takeCensus with cyclic breakdown structures.

// It specifically targets the pattern seen in the provided positive test case

// where `x["noFilename"] = x;` leads to a crash.

public class RemoveCyclicPropertyMutator: BaseInstructionMutator {

    public override init() {

        // Limit to one mutation at a time as fixing one cycle is the goal.

        super.init(name: "RemoveCyclicPropertyMutator", maxSimultaneousMutations: 1)

    }



    public override func canMutate(_ instr: Instruction) -> Bool {

        // Target SetProperty and SetComputedProperty instructions.

        guard instr.op is SetProperty || instr.op is SetComputedProperty else {

            return false

        }



        // Check for the cyclic assignment pattern: obj === value.

        if instr.op is SetProperty {

            // SetProperty(propertyName: String) -> obj, value

            // Inputs: obj (index 0), value (index 1)

            // The object being assigned to must be the same variable as the value being assigned.

            guard instr.numInputs == 2 else {

                // This should not happen for a valid SetProperty instruction.

                // If it does, we cannot safely determine the pattern.

                return false

            }

            return instr.input(0) == instr.input(1)

        } else if instr.op is SetComputedProperty {

            // SetComputedProperty -> obj, prop, value

            // Inputs: obj (index 0), prop (index 1), value (index 2)

            // The object being assigned to must be the same variable as the value being assigned.

            guard instr.numInputs == 3 else {

                // This should not happen for a valid SetComputedProperty instruction.

                 // If it does, we cannot safely determine the pattern.

               return false

            }

            return instr.input(0) == instr.input(2)

        }



        // Should not be reached if the initial guard works correctly.

        return false

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        // We know from canMutate that this instruction creates a cyclic reference.

        // Replace the value being assigned (which is the object itself) with null.



        let nullVar = b.loadNull()

        var newInouts = b.adopt(instr.inouts) // Adopt inputs from the original instruction



        if let op = instr.op as? SetProperty {

            // SetProperty inputs: [obj, value]

            // Replace value (index 1) with nullVar

            guard newInouts.count == 2, newInouts[0] == newInouts[1] else {

                // Precondition check based on canMutate logic

                logger.error("Inconsistent state: SetProperty inputs mismatch or not cyclic in mutate.")

                // Fallback: Append the original instruction to avoid crashing the fuzzer.

                 b.append(instr)

                return

            }

            newInouts[1] = nullVar

            b.trace("RemoveCyclicPropertyMutator: Replacing value for \(instr.op.name) (\(instr.input(0))[\"\(op.propertyName)\"] = \(instr.input(1))) with null (\(nullVar))")

            // Re-create the instruction with the modified inputs.

            // The operation itself (SetProperty with its propertyName) remains the same.

             b.append(Instruction(op, inouts: newInouts))

        } else if let op = instr.op as? SetComputedProperty {

            // SetComputedProperty inputs: [obj, prop, value]

            // Replace value (index 2) with nullVar

            guard newInouts.count == 3, newInouts[0] == newInouts[2] else {

                // Precondition check based on canMutate logic

                logger.error("Inconsistent state: SetComputedProperty inputs mismatch or not cyclic in mutate.")

                // Fallback: Append the original instruction to avoid crashing the fuzzer.

                b.append(instr)

                return

            }

            newInouts[2] = nullVar

            b.trace("RemoveCyclicPropertyMutator: Replacing value for \(instr.op.name) (\(instr.input(0))[\(instr.input(1))] = \(instr.input(2))) with null (\(nullVar))")

            // Re-create the instruction with the modified inputs.

            // The operation itself (SetComputedProperty) remains the same.

            b.append(Instruction(op, inouts: newInouts))

        } else {

            // Should not happen due to canMutate check

            logger.fatal("Unexpected instruction type \(instr.op.name) in RemoveCyclicPropertyMutator.mutate")

        }

        // The original instruction is not emitted; the new instruction with 'null' is appended instead.

    }

}
