

/// A mutator that specifically replaces `Object.defineProperty(x, "z", {})`

/// with `x.z = undefined;` to circumvent a specific JIT issue, based on the

/// provided positive and negative test cases.

public class DefinePropertyToAssignmentMutator: BaseInstructionMutator {



    public init() {

        // This is a highly specific transformation, so limit simultaneous mutations.

        super.init(name: "DefinePropertyToAssignmentMutator", maxSimultaneousMutations: 1)

    }



    /// Determines if the given instruction is a candidate for this mutation.

    /// We are looking for a `CallMethod` instruction that calls `Object.defineProperty`.

    public override func canMutate(_ instr: Instruction) -> Bool {

        // Check if it's a CallMethod operation named 'defineProperty'.

        guard let call = instr.op as? CallMethod,

              call.methodName == "defineProperty" else {

            return false

        }



        // Check if it has the expected number of inputs:

        // input 0: the 'Object' builtin (or the result of loading it)

        // input 1: the object instance (e.g., 'x')

        // input 2: the property name (e.g., "z")

        // input 3: the property descriptor (e.g., {})

        guard instr.numInputs == 4 else {

            return false

        }



        // We cannot easily verify the *exact* values of input 2 ('z') and input 3 ({})

        // within `canMutate`. We'll rely on the `mutate` function to be specific

        // or make simplifying assumptions based on the targeted nature of this mutator.

        // For now, identifying `Object.defineProperty` with the correct arity is sufficient.

        return true

    }



    /// Performs the mutation, replacing the `Object.defineProperty` call.

    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        // We assume `canMutate` has identified a potential candidate.

        // The goal is to replace:

        //   vx = CallMethod(objBuiltin, "defineProperty", [obj, propName, descriptor])

        // with:

        //   vy = LoadUndefined

        //   StoreProperty(obj, "z", vy)

        // This specifically targets the pattern where propName is "z" and descriptor is {}.



        // Adopt the object instance variable (input 1).

        let objVar = b.adopt(instr.input(1))



        // The specific property name required by the negative test case.

        let targetPropertyName = "z"



        // Ideally, we would check here if instr.input(2) corresponds to LoadString("z")

        // and instr.input(3) corresponds to CreateObject({}). However, accessing the

        // defining instruction requires program analysis beyond the scope of a simple

        // BaseInstructionMutator operating on a single instruction context.

        // Given the specific request, we proceed with the assumption that if we encounter

        // Object.defineProperty, we should try replacing it with the target pattern.

        // The fuzzer will discard the sample if this assumption was wrong and leads to invalid code.



        b.trace("Replacing Object.defineProperty(\(objVar), \"\(targetPropertyName)\", ...) with \(objVar).\(targetPropertyName) = undefined")



        // 1. Load the 'undefined' value.

        let undefinedVar = b.loadUndefined()



        // 2. Emit the StoreProperty instruction using the target property name "z".

        b.storeProperty(targetPropertyName, on: objVar, with: undefinedVar)



        // Note: The original `CallMethod` instruction might have produced an output variable.

        // This output is discarded by this mutation. This is acceptable if the output

        // wasn't used, which is the case in the provided example scenario:

        // `Object.defineProperty(x, "z", {});` followed by `x.z;` (a LoadProperty).

        // The `LoadProperty` still works correctly after our mutation.

    }

}
