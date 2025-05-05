

/// A mutator that specifically targets `y.toString(y)` calls and changes them to `y.toString()`

/// to circumvent a JIT optimization bug related to explicit base arguments in Number.prototype.toString.

public class CircumventToStringBaseOptMutator: BaseInstructionMutator {



    public init() {

        super.init(name: "CircumventToStringBaseOptMutator")

    }



    public override func canMutate(_ instr: Instruction) -> Bool {

        // Check if it's a CallMethod operation for "toString".

        guard let op = instr.op as? CallMethod, op.methodName == "toString" else {

            return false

        }



        // Check if it has exactly two inputs: the object and one argument.

        // Input 0: object (e.g., 'y')

        // Input 1: argument (e.g., 'y')

        guard instr.numInputs == 2 else {

            return false

        }



        // Optional, but matches the specific pattern: check if the object and argument are the same variable.

        // This makes the mutator highly specific to the pattern observed in the bug report.

        // If a broader mutator is desired (changing any obj.toString(arg) to obj.toString()),

        // this check can be removed.

        guard instr.input(0) == instr.input(1) else {

             return false

        }





        return true

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        // We know from canMutate that this is a CallMethod("toString") with 2 identical inputs.

        let callOp = instr.op as! CallMethod



        // Adopt the necessary variables from the original instruction.

        let objectVar = b.adopt(instr.input(0)) // This is 'y' in the example

        let outputVar = b.adopt(instr.output)



        // Create the new instruction: CallMethod("toString") with only the object as input (no arguments).

        b.append(Instruction(CallMethod(methodName: callOp.methodName), output: outputVar, inputs: [objectVar]))

    }

}
