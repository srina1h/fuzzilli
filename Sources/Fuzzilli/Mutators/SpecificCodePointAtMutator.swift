

/// A mutator that specifically targets `string.codePointAt(12)` calls,

/// replacing them with `if (string.length > 0) { string.codePointAt(0); }`

/// This is designed to workaround a specific JIT bug related to `codePointAt(12)`.

public class SpecificCodePointAtMutator: BaseInstructionMutator {



    public init() {

        super.init(name: "SpecificCodePointAtMutator")

    }



    public override func canMutate(_ instr: Instruction) -> Bool {

        // Check if the instruction is 'CallMethod' with method name 'codePointAt'

        // and takes exactly two inputs (the object and one argument).

        guard instr.op is CallMethod,

              let op = instr.op as? CallMethod,

              op.methodName == "codePointAt",

              instr.numInputs == 2 else {

            return false

        }

        // Further checks (like the argument value) require program context

        // and are deferred to the mutate method.

        return true

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        // Ensure the instruction is the one we expect.

        guard instr.op is CallMethod,

              let op = instr.op as? CallMethod,

              op.methodName == "codePointAt",

              instr.numInputs == 2 else {

            // Should not happen if canMutate is correct.

            return

        }



        let stringVar = instr.input(0)

        let argumentVar = instr.input(1)



        // Check if the argument variable originates from a 'LoadInteger 12' instruction.

        // This requires looking up the definition of the argument variable.

        guard let loadIntegerInstr = b.definition(of: argumentVar),

              loadIntegerInstr.op is LoadInteger,

              let loadIntegerOp = loadIntegerInstr.op as? LoadInteger,

              loadIntegerOp.value == 12 else {

            // The argument is not the integer literal 12, so this mutator doesn't apply.

            // Do not append anything to the builder, effectively skipping the mutation for this instruction.

            return

        }



        // We've confirmed the pattern: stringVar.codePointAt(12)



        // Append the replacement code structure:

        // if (stringVar.length > 0) { stringVar.codePointAt(0); }



        // 1. Create or get a variable holding the integer 0.

        let v0 = b.loadInt(0)



        // 2. Load the 'length' property of the original string variable.

        let vLength = b.loadProperty(stringVar, "length")



        // 3. Compare the length with 0 using GreaterThan.

        let vCond = b.compare(vLength, with: v0, using: .greaterThan)



        // 4. Build the If-block structure.

        b.buildIf(vCond) {

            // 5. Inside the If-block, call codePointAt(0) on the original string variable.

            // The result of the call is implicitly handled by the builder (assigned to a new variable if needed).

            // In the specific example case, the result was unused, so this is fine.

            b.callMethod(stringVar, methodName: "codePointAt", args: [v0])

        }



        // The original 'instr' (the CallMethod for codePointAt(12)) is effectively

        // replaced by the sequence of instructions just appended to the builder:

        // LoadInteger(0), LoadProperty("length"), Compare(>), BeginIf, CallMethod("codePointAt", [v0]), EndIf.

        b.trace("Applied SpecificCodePointAtMutator replacing \(instr)")

    }

}
