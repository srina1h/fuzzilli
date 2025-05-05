

/// A mutator that specifically targets a problematic `new SharedArrayBuffer(0, { "maxByteLength": 9999999999 })`

/// call and replaces it with `new SharedArrayBuffer(1024, { "maxByteLength": 8192 })`.

/// This is based on a specific crash scenario where the large maxByteLength combined with an initial size of 0

/// triggers a bug. The replacement values are chosen as potentially benign alternatives.

public class SharedArrayBufferZeroSizeMutator: BaseInstructionMutator {



    public init() {

        super.init(name: "SharedArrayBufferZeroSizeMutator")

    }



    public override func canMutate(_ instr: Instruction) -> Bool {

        // Check if the instruction is constructing an object with exactly two arguments.

        // SharedArrayBuffer(initialLength, options)

        return instr.op is Construct && instr.numInputs == 3 // constructor + 2 args

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        // This mutator replaces the specific problematic pattern.

        // We need to verify the structure matches the positive test case.



        // Input 0: The constructor function (should be SharedArrayBuffer)

        let constructorVar = instr.input(0)

        // Input 1: The initial length argument (should be 0)

        let initialLengthVar = instr.input(1)

        // Input 2: The options object (should be { "maxByteLength": 9999999999 })

        let optionsVar = instr.input(2)



        // 1. Check if the constructor is 'SharedArrayBuffer'.

        guard let constructorDefinition = b.definition(of: constructorVar),

              let loadBuiltinOp = constructorDefinition.op as? LoadBuiltin,

              loadBuiltinOp.builtinName == "SharedArrayBuffer" else {

            return // Not constructing SharedArrayBuffer

        }



        // 2. Check if the initial length is the integer literal 0.

        guard let initialLengthDefinition = b.definition(of: initialLengthVar),

              let loadIntOp1 = initialLengthDefinition.op as? LoadInteger,

              loadIntOp1.value == 0 else {

            return // Initial length is not 0

        }



        // 3. Check if the options object is created with specific properties.

        guard let optionsDefinition = b.definition(of: optionsVar),

              let createObjectOp = optionsDefinition.op as? CreateObjectWith else {

            // Options argument wasn't created by CreateObjectWith

            // It might be CreateObject, CreateObjectWithSpread, or something else.

            // This mutator specifically targets CreateObjectWith.

            return

        }



        // Check if the property names match ["maxByteLength"]

        guard createObjectOp.propertyNames == ["maxByteLength"] else {

            // Properties don't match the expected structure

            return

        }



        // 4. Check the value associated with "maxByteLength".

        // CreateObjectWith inputs correspond to property values in order.

        let maxByteLengthValueVar = optionsDefinition.input(0)

        guard let maxByteLengthDefinition = b.definition(of: maxByteLengthValueVar),

              let loadIntOp2 = maxByteLengthDefinition.op as? LoadInteger,

              loadIntOp2.value == 9999999999 else {

            // The value for maxByteLength is not 9999999999

            return

        }



        // If all checks passed, we've found the exact pattern. Now, replace it.

        b.trace("SharedArrayBufferZeroSizeMutator: Applying specific transformation")



        // Create the replacement values

        let newInitialLengthVar = b.loadInt(1024)

        let newMaxByteLengthValueVar = b.loadInt(8192)



        // Create the replacement options object

        // Using the same property name "maxByteLength" but with the new value variable.

        let newOptionsVar = b.createObject(with: ["maxByteLength": newMaxByteLengthValueVar])



        // Create the new Construct instruction, replacing the original one.

        // We reuse the original 'SharedArrayBuffer' constructor variable.

        b.construct(constructorVar, withArgs: [newInitialLengthVar, newOptionsVar])

    }

}
