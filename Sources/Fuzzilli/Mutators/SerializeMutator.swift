

/// A mutator that specifically targets the `serialize(a, [a])` pattern,

/// which causes a crash due to transferring the object being serialized.

/// It replaces this pattern with safer alternatives like `serialize(a)` or

/// `serialize(a, [])` or `serialize(a, [b])` where `b` is different from `a`.

public class SerializeMutator: BaseInstructionMutator {



    public init() {

        super.init(name: "SerializeMutator")

    }



    public override func canMutate(_ instr: Instruction) -> Bool {

        // Check if it's a CallFunction instruction with exactly 3 inputs:

        // input 0: the 'serialize' function/builtin variable

        // input 1: the object to serialize (let's call it 'a')

        // input 2: the transfer list array variable (let's call it 'v_array')

        guard instr.op is CallFunction, instr.numInputs == 3 else {

            return false

        }



        // We need access to the ProgramBuilder to inspect previous instructions

        // and variable types/definitions, which isn't directly available in canMutate.

        // So, we perform a preliminary check here and a more detailed check in mutate().

        // We could potentially check if input 0 is 'serialize' if builtins are identifiable early.

        // For now, we rely on the more detailed check in mutate().

        return true

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        // Ensure it's the CallFunction we are interested in (re-check from canMutate if necessary)

        guard instr.op is CallFunction, instr.numInputs == 3 else {

            return

        }



        let serializeFuncVar = instr.input(0)

        let objectToSerializeVar = instr.input(1)

        let transferListVar = instr.input(2)



        // Check if the function being called is likely 'serialize'.

        // This check might need adjustment based on how 'serialize' is loaded (e.g., LoadBuiltin).

        // A simple heuristic: check if the defining instruction for serializeFuncVar is LoadBuiltin.

        let funcDef = b.definition(of: serializeFuncVar)

        guard funcDef.op is LoadBuiltin, (funcDef.op as! LoadBuiltin).builtinName == "serialize" else {

            // Or maybe it's just a variable holding the function, this check might be too strict.

            // Consider removing this check if serialize can be obtained differently.

            // For this specific scenario based on the bug report, assuming LoadBuiltin is likely.

            b.trace("SerializeMutator: Input 0 is not LoadBuiltin('serialize')")

            return

        }





        // Find the instruction that defined the transferListVar (input 2)

        let transferListDef = b.definition(of: transferListVar)



        // Check if the transfer list was created with CreateArray and has exactly one element

        guard transferListDef.op is CreateArray, transferListDef.numInputs == 1 else {

            b.trace("SerializeMutator: Transfer list variable \(transferListVar) is not defined by CreateArray with 1 input")

            return

        }



        // Get the single variable that was put into the array

        let transferredObjectVar = transferListDef.input(0)



        // THE CRITICAL CHECK: Is the object being serialized the same as the single object in the transfer list?

        guard objectToSerializeVar == transferredObjectVar else {

            b.trace("SerializeMutator: Object being serialized \(objectToSerializeVar) is different from the transferred object \(transferredObjectVar)")

            return

        }



        // If we reached here, we found the pattern: serialize(a, [a])



        b.trace("SerializeMutator: Found pattern serialize(\(objectToSerializeVar), [\(objectToSerializeVar)]) at index \(instr.index). Mutating.")



        // Choose a replacement strategy randomly

        let strategy = Int.random(in: 0..<3)



        switch strategy {

        case 0:

            // Strategy 1: Replace serialize(a, [a]) with serialize(a)

            b.trace("SerializeMutator: Replacing with serialize(\(objectToSerializeVar))")

            b.callFunction(serializeFuncVar, args: [objectToSerializeVar])



        case 1:

            // Strategy 2: Replace serialize(a, [a]) with serialize(a, [])

            b.trace("SerializeMutator: Replacing with serialize(\(objectToSerializeVar), [])")

            let emptyArray = b.createArray([])

            b.callFunction(serializeFuncVar, args: [objectToSerializeVar, emptyArray])



        case 2:

            // Strategy 3: Replace serialize(a, [a]) with serialize(a, [b]) where b != a

            b.trace("SerializeMutator: Attempting to replace with serialize(\(objectToSerializeVar), [b]) where b != \(objectToSerializeVar)")

            // Try to find *any* other variable to put in the transfer list.

            // Ideally, it should be another serializable object, but any variable works to avoid the specific crash.

            if let differentVar = b.randomVariable(excluding: [objectToSerializeVar, serializeFuncVar, transferListVar]) {

                 b.trace("SerializeMutator: Found different variable \(differentVar). Replacing with serialize(\(objectToSerializeVar), [\(differentVar)])")

                 let newTransferList = b.createArray([differentVar])

                 b.callFunction(serializeFuncVar, args: [objectToSerializeVar, newTransferList])

            } else {

                // Fallback if no other variable is available (unlikely in most programs)

                // Use strategy 1 or 2 as fallback

                b.trace("SerializeMutator: Could not find a different variable. Falling back to serialize(\(objectToSerializeVar))")

                b.callFunction(serializeFuncVar, args: [objectToSerializeVar])

            }

        default:

            fatalError("Invalid strategy")

        }



        // Optionally, add gc() and print() as suggested in the negative test case comments

        // Check if 'gc' builtin is available and call it

        if let gcBuiltin = b.loadBuiltin("gc") {

            b.callFunction(gcBuiltin)

        }

        // Add a print statement

         let message = b.loadString("Serialization completed without transferring the object itself.")

         b.print(message)



        // Remove the original instruction

        b.remove(instr)

    }

}
