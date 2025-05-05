

// This mutator specifically targets the crash pattern identified in the bug report:

// A call to `Number.prototype.toString` with a variable as the radix argument.

// It replaces the variable radix with a constant (10) and adds a simple

// operation afterwards to potentially alter JIT behavior slightly, mirroring

// the structure of the provided negative test case.

public class FixToStringRadixMutator: BaseInstructionMutator {



    public init() {

        super.init(name: "FixToStringRadixMutator")

    }



    public override func canMutate(_ instr: Instruction) -> Bool {

        // Check if it's a CallMethod operation for the property "toString"

        guard instr.op is CallMethod,

              let op = instr.op as? CallMethod,

              op.propertyName == "toString" else {

            return false

        }



        // Check if it has at least two inputs: the object instance and the radix argument.

        // obj.toString(radix) -> inputs[0] = obj, inputs[1] = radix

        guard instr.numInputs >= 2 else {

            return false

        }



        // The core condition: we are interested if the radix argument (input 1)

        // is *not* already a constant integer literal. Fuzzilli doesn't directly

        // tell us if an input *variable* originated from a constant, but we can

        // apply this mutator optimistically. If the input variable *was* a constant,

        // this mutator might not change behavior much, but it's specifically

        // designed for cases where the radix is a variable holding a problematic value (like 2).

        // We don't need a complex check here; the structure match is enough.

        return true

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        guard let callOp = instr.op as? CallMethod, callOp.propertyName == "toString", instr.numInputs >= 2 else {

            fatalError("Invalid instruction passed to FixToStringRadixMutator: \(instr)")

        }



        // Keep track of the original variable used as radix.

        // Inputs for CallMethod: [obj, arg1, arg2, ...]

        // We need the variable for the radix, which is at index 1.

        let originalRadixVar = instr.input(1)



        // Adopt the inputs/outputs from the original instruction.

        var inouts = b.adopt(instr.inouts)



        // Create a constant integer 10 to use as the new radix.

        let constantRadix = b.buildInt(10)



        // Replace the original radix variable (inputs[1]) with the constant.

        inouts[1] = constantRadix



        // Build the new CallMethod instruction with the constant radix.

        // Reuse the original operation configuration and flags.

        let newInstr = Instruction(callOp, inouts: inouts, flags: instr.flags)

        b.append(newInstr)



        // Add the trivial operation 'x = x + 1;' using the original radix variable.

        // Ensure the original variable is still valid (it should be).

        let one = b.buildInt(1)

        let sum = b.buildBinaryOperation(originalRadixVar, one, .Add)

        b.buildReassign(originalRadixVar, sum)

    }

}
