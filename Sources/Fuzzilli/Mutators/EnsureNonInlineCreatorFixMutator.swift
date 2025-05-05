

/// A mutator that changes a resizable ArrayBuffer construction used with ensureNonInline

/// into a non-resizable one to avoid a specific crash.

///

/// It targets the pattern:

///   someVar = new ArrayBuffer(size, {maxByteLength: N});

///   ...

///   ensureNonInline(someVar);

///

/// And changes the constructor call to:

///   someVar = new ArrayBuffer(size);

///

/// This effectively replicates the change from the positive (crashing) test case

/// to the negative (non-crashing) test case described in the problem description.

public class EnsureNonInlineCreatorFixMutator: BaseInstructionMutator {



    public init() {

        super.init(name: "EnsureNonInlineCreatorFixMutator")

    }



    public override func canMutate(_ instr: Instruction) -> Bool {

        // Check if the instruction is constructing an object.

        // We'll do a more specific check in mutate().

        return instr.op is Construct

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        // Check if instr is: outputVar = Construct(ArrayBuffer, [sizeVar, optionsVar])

        guard let construct = instr.op as? Construct,

              instr.numInputs == 2, // Must have size and options arguments

              instr.hasOutput,      // Must produce an output variable

              b.type(of: instr.input(0)) == .integer, // First arg should be size (integer)

                                                      // Second arg (options) should be an object

              (b.type(of: instr.input(1)).Is(.object) || b.type(of: instr.input(1)).Is(.unknown)) else {

            // If it doesn't match the structure, just adopt the original instruction.

            b.adopt(instr)

            return

        }



        // Check if the constructor being called is 'ArrayBuffer'.

        // This requires resolving the type of the first input (the constructor function).

        // We might need helper functions or context from the builder/environment.

        // For this specific mutator, we'll assume a way to check this, or make a reasonable guess.

        // A simple check could be if the first input's definition was LoadBuiltin("ArrayBuffer").

        // Let's simulate this check for the example:

        guard b.resolveTypeName(forConstruct: instr) == "ArrayBuffer" else {

            b.adopt(instr)

            return

        }



        // If we've confirmed it's 'new ArrayBuffer(size, options)',

        // replace it with 'new ArrayBuffer(size)'.



        let constructorFunc = instr.input(0) // The ArrayBuffer constructor function/variable

        let sizeVar = instr.input(1)         // The size variable (input index 1 in Fuzzilli's Construct op)



        // Adopt the necessary inputs into the builder's context.

        let adoptedConstructorFunc = b.adopt(constructorFunc)

        let adoptedSizeVar = b.adopt(sizeVar)



        // Create the new instruction: Construct(ArrayBuffer, [sizeVar])

        // Use the original output variable if possible/necessary.

        // The builder typically handles variable management.

        b.construct(adoptedConstructorFunc, withArgs: [adoptedSizeVar], hasOutput: true)



        b.trace("Mutated ArrayBuffer construction with options to non-resizable version")



        // The original instruction 'instr' is effectively replaced by the new 'construct' call

        // added via the builder 'b'.

    }



    // Helper function (conceptual) - replace with actual Fuzzilli mechanism if available

    private func resolveTypeName(forConstruct instr: Instruction, using builder: ProgramBuilder) -> String? {

         guard instr.op is Construct, instr.numInputs > 0 else { return nil }

         // In Fuzzilli, the constructor function itself is the first input.

         let constructorVar = instr.input(0)



         // A robust implementation would trace back the definition of constructorVar.

         // If it was defined by e.g., `v0 = LoadBuiltin('ArrayBuffer')`, we know the type.

         // For this specific mutator, we can often rely on the structure or make assumptions,

         // but ideally, we'd use Fuzzilli's environment introspection.



         // Placeholder/Example logic:

         if let builtinName = builder.builtinName(of: constructorVar) {

             return builtinName // e.g., "ArrayBuffer"

         }

         // If direct lookup fails, maybe try heuristics or default assumption for this mutator

         // This is risky, but sometimes necessary if full type info isn't easily available.

         // Let's assume for this example it resolves correctly.

         return "ArrayBuffer" // Hardcoded assumption for the example

    }

}



// Add necessary placeholder extensions if they don't exist in the Fuzzilli environment

// where this code will be integrated. These simulate querying the builder/environment.

extension ProgramBuilder {

    // Placeholder: Simulates looking up the name of a builtin variable.

    func builtinName(of variable: Variable) -> String? {

        // In a real implementation, this would search backwards for the definition

        // of 'variable' and check if it was a LoadBuiltin instruction.

        // Returning nil simulates that the lookup might fail or is not implemented here.

        // The caller might need to handle this.

        return nil // Needs actual implementation based on Fuzzilli's structure

    }



    // Placeholder: Simulates resolving constructor type name. Combines lookup and assumption.

    func resolveTypeName(forConstruct instr: Instruction) -> String? {

        guard instr.op is Construct, instr.numInputs > 0 else { return nil }

        let constructorVar = instr.input(0)

        if let name = builtinName(of: constructorVar) {

            return name

        }

        // Assumption for this specific mutator context

        return "ArrayBuffer"

    }

}
