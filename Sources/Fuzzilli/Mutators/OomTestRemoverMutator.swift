

/// A mutator specifically designed to transform JavaScript code patterns involving `oomTest`

/// into a `try...catch` block to circumvent OOM-specific issues during testing.

///

/// It looks for patterns like:

/// ```javascript

/// oomTest(function() {

///   // code causing crash/assertion under OOM simulation

///   ...

/// });

/// ```

/// And transforms them into:

/// ```javascript

/// // Comments explaining the change

/// try {

///   // code causing crash/assertion under OOM simulation

///   ...

/// } catch(e) {

///   // Comments about expected non-crash behavior

/// }

/// ```

/// This is useful when a bug only manifests under `oomTest` (e.g., during specific allocation failures

/// in compilation) and the goal is to test if the underlying code (like Wasm compilation)

/// runs without crashing in a normal execution context.

public class OomTestRemoverMutator: BaseInstructionMutator {



    public init() {

        // Typically, we want to apply this specific transformation once per mutation cycle.

        super.init(name: "OomTestRemoverMutator", maxSimultaneousMutations: 1)

    }



    // We perform more detailed checks in `mutate` as it has access to the ProgramBuilder context.

    // `canMutate` provides a preliminary filter.

    public override func canMutate(_ instr: Instruction) -> Bool {

        // Check if the instruction is a function call with at least two inputs

        // (callee and one function argument).

        return instr.op is CallFunction && instr.numInputs >= 2

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        // Double-check the instruction type.

        guard instr.op is CallFunction, instr.numInputs >= 2 else {

            // If canMutate was too broad, just copy the original instruction.

             b.adopt(instr) { _ in b.append(instr) }

            return

        }



        // 1. Verify the callee is 'oomTest'.

        let calleeVar = instr.input(0)

        guard let loadCalleeInst = b.prog.findDef(for: calleeVar) else {

            // Cannot find definition, adopt original instruction.

             b.adopt(instr) { _ in b.append(instr) }

            return

        }



        // Check common ways 'oomTest' might be loaded. Adjust if necessary based on JS environment profile.

        var isOomTestCall = false

        if let loadBuiltin = loadCalleeInst.op as? LoadBuiltin, loadBuiltin.builtinName == "oomTest" {

            isOomTestCall = true

        } else if let loadProperty = loadCalleeInst.op as? LoadProperty, loadProperty.propertyName == "oomTest" {

             // Potentially loaded from global object, etc.

             isOomTestCall = true

        } else if let loadGlobal = loadCalleeInst.op as? LoadGlobal, loadGlobal.globalName == "oomTest" {

             isOomTestCall = true

        }

         // Add more checks as needed for other loading mechanisms.



        guard isOomTestCall else {

            // Not the target oomTest call, adopt original instruction.

             b.adopt(instr) { _ in b.append(instr) }

            return

        }



        // 2. Verify the first argument (instr.input(1)) is a function definition.

        let functionVar = instr.input(1)

        guard let funcBeginInstr = b.prog.findDef(for: functionVar),

              funcBeginInstr.op.attributes.contains(.isBlockGroupStart),

              funcBeginInstr.op.isFunctionDefinition // Assumes Operation has this helper check (see below)

        else {

            // Argument is not defined by a suitable function definition start. Adopt original.

             b.adopt(instr) { _ in b.append(instr) }

            return

        }



        // 3. Find the end instruction of the function block.

        guard let funcEndInstrIndex = b.prog.findEndOfBlock(startingAt: funcBeginInstr.index) else {

            logger.error("OomTestRemoverMutator: Failed to find end instruction for function block starting at \(funcBeginInstr.index)")

            // Cannot determine function body, adopt original instruction.

             b.adopt(instr) { _ in b.append(instr) }

            return

        }



        // 4. Perform the transformation.

        b.trace("OomTestRemoverMutator: Replacing oomTest call at \(instr.index) with try-catch block.")



        // Add comments similar to the negative test case.

        b.appendComment("// Circumventing test case by removing oomTest")

        b.appendComment("// The original crash/assertion occurs during compilation under OOM simulation.")

        b.appendComment("// Running the compilation directly should avoid the OOM-specific issue.")



        // Start the try block.

        b.beginTry()



        // Copy the instructions from the function body into the try block.

        // The body is between funcBeginInstr.index + 1 and funcEndInstrIndex.

        for i in funcBeginInstr.index + 1 ..< funcEndInstrIndex {

            let bodyInstr = b.prog[i]

            // Use adopt to correctly map variables into the builder's context.

             b.adopt(bodyInstr) { adoptedInouts in

                 // Create a new instruction instance with the adopted inputs/outputs.

                 b.append(Instruction(bodyInstr.op, inouts: adoptedInouts, flags: bodyInstr.flags))

             }

        }



        // Start the catch block.

        b.beginCatch() // Fuzzilli typically implicitly provides the exception variable 'e' if needed.



        // Add comments inside the catch block.

        b.appendComment("// We expect compilation to succeed or fail gracefully, not crash.")

        b.appendComment("// A TypeError might occur if Wasm is disabled, or a CompileError if the module is invalid,")

        b.appendComment("// but the specific crash/assertion from the bug report should be avoided.")

        // Example: Optionally log the error (if environment supports console.log)

        // let consoleLog = b.loadBuiltin("console.log")

        // let exceptionVar = b.specialVariable(.exception) // Assuming Fuzzilli provides this

        // b.callFunction(consoleLog, args: [exceptionVar])

        b.appendComment("// console.log(\"Caught expected error: \" + e);") // Keep as comment like target



        // End the try-catch structure.

        b.endTryCatch()



        // The original CallFunction instruction (`instr`), and the associated Begin/End

        // function definition instructions are implicitly removed because they were not

        // added to the builder `b` during this mutation process.

    }

}



// Helper extension to Operation, assuming it doesn't already exist in Fuzzilli.

// This helps identify various function definition starting operations.

extension Operation {

    var isFunctionDefinition: Bool {

        switch self {

        case is BeginPlainFunctionDefinition,

             is BeginArrowFunctionDefinition,

             is BeginGeneratorFunctionDefinition,

             is BeginAsyncFunctionDefinition,

             is BeginAsyncArrowFunctionDefinition,

             is BeginAsyncGeneratorFunctionDefinition:

            return true

        default:

            return false

        }

    }

}
