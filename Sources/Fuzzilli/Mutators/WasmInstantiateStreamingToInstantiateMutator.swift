

// This mutator specifically targets the pattern observed in the crash:

// A call to WebAssembly.instantiateStreaming.

// It replaces it with a synchronous WebAssembly.instantiate call wrapped

// in a try-catch block to avoid crashes related to off-thread promise

// resolution during OOM conditions, mimicking the structure of the

// provided negative test case.

public class WasmInstantiateStreamingToInstantiateMutator: BaseInstructionMutator {



    public init() {

        super.init(name: "WasmInstantiateStreamingToInstantiate")

    }



    // Determines if this mutator can be applied to a given instruction.

    override public func canMutate(_ instr: Instruction) -> Bool {

        // We are looking for 'WebAssembly.instantiateStreaming(wasmCode)'

        if let op = instr.op as? CallBuiltin {

            // Check if the builtin name matches and it has exactly one input (the wasm code).

            return op.builtinName == "WebAssembly.instantiateStreaming" && instr.numInputs == 1

        }

        return false

    }



    // Performs the mutation.

    override public func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        // Sanity check, although canMutate should ensure this.

        guard instr.numInputs == 1 else {

            // Fallback: If the instruction doesn't match expectations,

            // just append the original instruction to avoid breaking the program.

            b.adopt(instr)

            return

        }



        // Get the input variable (representing the wasm code) from the original instruction.

        // 'adopt' makes the variable available in the builder's context.

        let wasmCodeArg = b.adopt(instr.input(0))



        // Start a try block.

        b.beginTry()



        // Build the replacement instruction: WebAssembly.instantiate(wasmCode).

        // The negative test case ignores the result of instantiate (which is an object

        // containing module and instance). So, we model this as a call without an output variable.

        b.callBuiltin("WebAssembly.instantiate", args: [wasmCodeArg])



        // Build the catch block.

        b.beginCatch()

        // The negative test case has an empty catch block, simply ignoring errors

        // like OOM that might occur during the synchronous instantiation itself.

        // We could optionally capture the exception variable here if needed for other scenarios:

        // let exception = b.catchException()

        b.endCatch() // This concludes the try-catch structure.



        // The original 'instr' (WebAssembly.instantiateStreaming call) is effectively

        // replaced by the sequence of instructions added to the builder:

        // BeginTry, CallBuiltin(WebAssembly.instantiate), BeginCatch, EndCatch.

    }

}
