

// A mutator that specifically targets WeakMap.set calls using a Symbol as a key

// and replaces the Symbol key with a newly created Object key.

// This is designed to transform the structure found in the positive test case

// towards the structure of the negative test case, addressing the core difference

// believed to be related to the crash (Symbol keys in WeakMap during GC).

public class WeakMapSymbolToObjectKeySwapMutator: BaseInstructionMutator {



    public init() {

        super.init(name: "WeakMapSymbolToObjectKeySwapMutator")

    }



    // We only want to mutate CallMethod instructions.

    override public func canMutate(_ instr: Instruction) -> Bool {

        return instr.op is CallMethod

    }



    override public func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        // Ensure it's a CallMethod for "set" with at least object, key, value inputs.

        guard let callOp = instr.op as? CallMethod,

              callOp.methodName == "set",

              instr.numInputs >= 3 else {

            // If not the target pattern, just adopt the original instruction.

            b.adopt(instr)

            return

        }



        let keyVar = instr.input(1) // The key is the second input (index 1)



        // Check if the key variable originates from a LoadSymbol instruction.

        // This requires looking up the definition of the key variable.

        guard let keyCreationInstr = b.findDef(for: keyVar),

              keyCreationInstr.op is LoadSymbol else {

            // The key wasn't created by LoadSymbol, so don't mutate.

            b.adopt(instr)

            return

        }



        // If we found WeakMap.set(symbol, value):

        b.trace("Applying WeakMapSymbolToObjectKeySwapMutator to \(instr)")



        // 1. Adopt the original instruction first. This ensures its inputs are available

        //    and it's part of the current program trace.

        b.adopt(instr)



        // 2. Create a new plain object `{}`. This will serve as the new key.

        //    This instruction is inserted logically *before* the CallMethod.

        let newObjectKey = b.createObject(with: [:])



        // 3. Build the input list for the new CallMethod instruction.

        //    It's the same as the original, but input at index 1 (the key) is replaced.

        var newInputs = Array(instr.inputs)

        newInputs[1] = newObjectKey // Replace symbol variable with the new object variable



        // 4. Create the new CallMethod instruction with the modified inputs.

        //    It uses the same operation and keeps the original outputs.

        let newSetCall = Instruction(instr.op, inouts: newInputs + instr.outputs)



        // 5. Replace the original (adopted) instruction with the new one in the program trace.

        //    This effectively swaps the original `m58.set(sym, ...)` with `m58.set(objKey, ...)`.

        b.replace(instr, with: newSetCall)



        b.trace("Replaced Symbol key with Object key in WeakMap.set call")



        // Note: This mutator *only* performs the key swap. Other changes seen in the

        // negative test case (like adding try-catch blocks, removing function arguments,

        // adding a final gc()) would typically be handled by separate, more general-purpose

        // Fuzzilli mutators (e.g., WrapInTryCatchMutator, ArgumentRemoverMutator,

        // InstructionAppenderMutator) applied randomly during the fuzzing process.

        // Combining all those changes into one specific mutator is brittle and generally

        // not the standard Fuzzilli approach. This mutator focuses on the core change

        // related to the crash trigger.

    }

}
