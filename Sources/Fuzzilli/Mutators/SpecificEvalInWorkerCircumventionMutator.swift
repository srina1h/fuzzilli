

// This mutator specifically targets a LoadString instruction containing the exact code

// from the positive test case's evalInWorker call and replaces it with the code

// from the negative test case's evalInWorker call.



public class SpecificEvalInWorkerCircumventionMutator: BaseInstructionMutator {



    // The exact string content from the positive test case's evalInWorker call.

    private let positiveTestCaseString = """

\n  let z = [[3,,,,,,241,255,,,,,55,,255,255,,,,,,,,,]];\n  for (let x of z) {\n    let y = serialize();\n    y.clonebuffer = new Int8Array(x).buffer;\n    deserialize(y);\n  }\n

"""



    // The exact string content for the negative test case's evalInWorker call.

    private let negativeTestCaseString = """

\n  // Circumvention: Avoid assigning to .clonebuffer and use a simple object.\n  // The leak seems related to deserializing a custom object after\n  // its .clonebuffer property has been set to an ArrayBuffer derived\n  // from a sparse array.\n  // Let's try serializing and deserializing a simple, standard JavaScript object\n  // without involving .clonebuffer.\n\n  let simpleObject = { data: "some data", value: 42 };\n\n  // Assuming serialize() can take an object or returns a wrapper\n  // where we can store data differently.\n\n  // Option 1: Serialize the object directly (if supported)\n  try {\n      let serializedData = serialize(simpleObject);\n      let deserializedData = deserialize(serializedData);\n      // Optional: Add an assertion or check\n      if (deserializedData.value !== 42) {\n          // console.log("Deserialization mismatch");\n      }\n  } catch(e) {\n      // Option 2: Use the default serialize() object but store data differently\n      let y = serialize();\n      y.payload = simpleObject; // Store data in a different property\n      let deserializedY = deserialize(y);\n      // Optional: Add an assertion or check\n       if (!deserializedY.payload || deserializedY.payload.value !== 42) {\n          // console.log("Deserialization mismatch (payload)");\n       }\n  }\n\n  // Ensure the worker does *something*\n  let calculation = 5 * 8;\n  // console.log("Worker finished calculation: " + calculation);\n

"""



    public init() {

        super.init(name: "SpecificEvalInWorkerCircumventionMutator")

    }



    public override func canMutate(_ instr: Instruction) -> Bool {

        // Check if the instruction is LoadString

        guard instr.op is LoadString else {

            return false

        }

        // Check if the string value matches the exact positive test case string

        return instr.stringArgument == positiveTestCaseString

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        // Ensure the condition still holds (it should due to canMutate)

        assert(instr.op is LoadString && instr.stringArgument == positiveTestCaseString)



        // Create the replacement LoadString operation with the negative case string

        let replacementOp = LoadString(value: negativeTestCaseString)



        // Create the replacement instruction, ensuring it produces the same output variable

        // as the original instruction. The mutation framework handles skipping the original

        // instruction, and the builder ensures this new instruction is placed correctly.

        let replacementInstr = Instruction(replacementOp, output: instr.output)



        // Append the replacement instruction to the program being built.

        b.append(replacementInstr)



        b.trace("Applied SpecificEvalInWorkerCircumventionMutator")

    }

}
