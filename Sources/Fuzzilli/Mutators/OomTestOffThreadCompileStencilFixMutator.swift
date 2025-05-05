

/// A mutator that specifically targets the pattern `eval('oomTest(function(){offThreadCompileToStencil("")})');`

/// and replaces it with a structure that calls `offThreadCompileToStencil` directly within eval,

/// guarded by a type check, and adds some trivial operations.

///

/// This is designed to turn the specific positive test case (causing a leak due to oomTest)

/// into the provided negative test case (circumventing the oomTest).

public class OomTestOffThreadCompileStencilFixMutator: BaseInstructionMutator {



    public init() {

        super.init(name: "OomTestOffThreadCompileStencilFixMutator")

    }



    public override func canMutate(_ instr: Instruction) -> Bool {

        // Check if it's a CallFunction instruction for 'eval'.

        guard instr.op is CallFunction,

              let functionName = (instr.op as! CallFunction).functionName,

              functionName == "eval",

              instr.numInputs == 1 else {

            return false

        }



        // Check if the input to 'eval' comes directly from a LoadString instruction

        // with the specific problematic pattern.

        // We need the ProgramBuilder context here to trace the input variable,

        // so the actual check needs to happen within the mutate function where

        // the builder is available. We return true here to indicate potential,

        // and refine the check in mutate.

        // A more robust check could involve looking at preceding instructions,

        // but for simplicity in this context, we'll check in mutate.

        return true

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        // Re-verify the conditions from canMutate, now with access to the builder to check the input source.

        guard instr.op is CallFunction,

              let functionName = (instr.op as! CallFunction).functionName,

              functionName == "eval",

              instr.numInputs == 1 else {

            // Should not happen if canMutate was called first, but good practice.

            return

        }



        // Get the variable passed to eval

        let evalArgVar = instr.input(0)



        // Find the instruction that defined this variable

        guard let definingInstr = b.definition(of: evalArgVar),

              definingInstr.op is LoadString,

              let loadedString = (definingInstr.op as! LoadString).value else {

            // The input to eval wasn't produced by a LoadString, or the string is null.

            // We can't apply this specific mutation.

             b.adopt(instr) // Keep the original instruction

            return

        }



        // Check if the string matches the exact positive test case pattern

        let targetString = "oomTest(function(){offThreadCompileToStencil(\"\")})"

        guard loadedString == targetString else {

            // The string content doesn't match the specific pattern we want to replace.

             b.adopt(instr) // Keep the original instruction

            return

        }



        // If we reached here, the instruction matches the pattern.

        // Do not adopt the original instruction, replace it with the new code block.



        // Build the negative test case structure:

        b.trace("Applying OomTestOffThreadCompileStencilFixMutator to instruction \(instr.index)")



        // 1. Check typeof offThreadCompileToStencil === 'function'

        let offThreadCompileFunc = b.loadBuiltin("offThreadCompileToStencil")

        let typeOfFunc = b.typeOf(offThreadCompileFunc)

        let functionString = b.loadString("function")

        let condition = b.compare(typeOfFunc, functionString, with: .equal)



        b.beginIf(condition) {

            // 2. If true: eval('offThreadCompileToStencil("function test() { return 1 + 1; }")');

            let innerEvalString = b.loadString("offThreadCompileToStencil(\"function test() { return 1 + 1; }\")")

            b.callFunction("eval", withArgs: [innerEvalString])

        }

        b.beginElse() {

            // 3. If false: let x = 1;

            let x = b.loadInt(1)

            // Fuzzilli needs variables to be used, though this simple assignment might be optimized away.

            // In a real scenario, you might want to print x or use it minimally.

            // For this specific transformation, we just declare it as per the example.

            // We don't explicitly need to use 'x' further according to the target code.

        }

        b.endIf()



        // 4. Add trivial operations: let y = 2; let z = y + 3;

        let y = b.loadInt(2)

        let three = b.loadInt(3)

        let z = b.binary(y, three, with: .Add)

        // Again, 'z' isn't explicitly used in the target, but defining it matches the structure.

        // A real fuzzer might want to ensure generated code has effects, e.g., by printing z.

    }

}
