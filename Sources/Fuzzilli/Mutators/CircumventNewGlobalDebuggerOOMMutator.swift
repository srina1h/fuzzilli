

/// A mutator that identifies the specific pattern `newGlobal().Debugger.call().addAllGlobalsAsDebuggees()`

/// and replaces it with a safer sequence that creates the debugger and global separately

/// and uses `dbg.addDebuggee(g)` instead of `addAllGlobalsAsDebuggees`.

/// This is designed to circumvent a crash observed when the original pattern runs under OOM conditions,

/// particularly avoiding the problematic `addAllGlobalsAsDebuggees` call immediately after `newGlobal`.

public class CircumventNewGlobalDebuggerOOMMutator: BaseMutator {



    public init() {

        super.init(name: "CircumventNewGlobalDebuggerOOMMutator")

    }



    public override func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Program? {

        var found = false

        var startIndex = 0

        var endIndex = 0



        // Search for the specific contiguous instruction sequence corresponding to the problematic pattern.

        // The pattern in FuzzIL typically looks like:

        // v0 = LoadBuiltin("newGlobal")

        // v1 = CallFunction(v0)                     // newGlobal()

        // v2 = LoadProperty(v1, "Debugger")        // .Debugger

        // v3 = CallMethod(v2, "call", [v1])        // .call() [with global as this]

        //      CallMethod(v3, "addAllGlobalsAsDebuggees", []) // .addAllGlobalsAsDebuggees()

        for i in 0..<(program.code.count - 4) { // Need at least 5 instructions for the pattern

             if let end = findContiguousSequence(startingAt: i, in: program) {

                found = true

                startIndex = i

                endIndex = end

                break // Found the first occurrence, apply the mutation and stop searching

             }

        }



        guard found else {

            return nil // Pattern not found in the program

        }



        // Build the mutated program

        // Adopt instructions from the original program up to the start of the sequence

        b.adopting(from: program, upTo: startIndex)



        // Insert the replacement code sequence:

        // JavaScript equivalent:

        // let dbg = new Debugger();

        // let g = newGlobal({newCompartment: true});

        // if (g !== null) { // Handle potential OOM during newGlobal

        //    dbg.addDebuggee(g);

        // }

        let dbgCls = b.loadBuiltin("Debugger")

        let dbg = b.construct(dbgCls) // let dbg = new Debugger();



        let options = b.createObject(with: ["newCompartment": b.loadBool(true)]) // {newCompartment: true}

        let newGlobalFunc = b.loadBuiltin("newGlobal") // Get the newGlobal function itself

        let g = b.callFunction(newGlobalFunc, args: [options]) // let g = newGlobal({newCompartment: true});



        let nullVal = b.loadNull()

        let cond = b.compare(g, nullVal, .notEqual) // g !== null

        b.beginIf(cond)

        b.callMethod(dbg, "addDebuggee", args: [g]) // dbg.addDebuggee(g);

        b.endIf()



        // Adopt the rest of the original program, skipping the instructions that formed the matched pattern

        b.adopting(from: program, after: endIndex)



        // Return the finalized mutated program

        return b.finalize()

    }



    /// Finds the specific contiguous 5-instruction sequence:

    /// LoadBuiltin("newGlobal") -> CallFunction -> LoadProperty("Debugger") -> CallMethod("call") -> CallMethod("addAllGlobalsAsDebuggees")

    /// Returns the end index (inclusive) of the sequence if found at the specified start index, otherwise nil.

    private func findContiguousSequence(startingAt i: Int, in program: Program) -> Int? {

        // Ensure there are enough instructions remaining in the program for the sequence

        guard i + 4 < program.code.count else { return nil }



        let instr0 = program.code[i]     // Expected: LoadBuiltin("newGlobal")

        let instr1 = program.code[i + 1] // Expected: CallFunction(v0)

        let instr2 = program.code[i + 2] // Expected: LoadProperty(v1, "Debugger")

        let instr3 = program.code[i + 3] // Expected: CallMethod(v2, "call", [v1])

        let instr4 = program.code[i + 4] // Expected: CallMethod(v3, "addAllGlobalsAsDebuggees", [])



        // Check instr0: Must be LoadBuiltin("newGlobal") and produce an output variable (v0)

        guard let op0 = instr0.op as? LoadBuiltin,

              op0.builtinName == "newGlobal",

              instr0.hasOutput else { return nil }

        let v0 = instr0.output



        // Check instr1: Must be CallFunction using v0, with no arguments, producing an output (v1)

        guard let op1 = instr1.op as? CallFunction,

              instr1.numInputs >= 1, // At least the function input

              instr1.input(0) == v0,

              instr1.numArguments == 0,

              instr1.hasOutput else { return nil }

        let v1 = instr1.output // This is the new global object



        // Check instr2: Must be LoadProperty "Debugger" from v1, producing an output (v2)

        guard let op2 = instr2.op as? LoadProperty,

              op2.propertyName == "Debugger",

              instr2.numInputs == 1,

              instr2.input(0) == v1,

              instr2.hasOutput else { return nil }

        let v2 = instr2.output // This is the Debugger property/constructor



        // Check instr3: Must be CallMethod "call" on v2, with v1 as the single argument (the 'this' value), producing output v3

        guard let op3 = instr3.op as? CallMethod,

              op3.methodName == "call",

              instr3.numInputs == 2,    // obj (v2) + 1 arg (v1)

              instr3.input(0) == v2,    // The object/function providing .call

              instr3.numArguments == 1,

              instr3.input(1) == v1,    // The 'this' argument for .call()

              instr3.hasOutput else { return nil }

        let v3 = instr3.output // This is the debugger instance



        // Check instr4: Must be CallMethod "addAllGlobalsAsDebuggees" on v3, with no arguments

        guard let op4 = instr4.op as? CallMethod,

              op4.methodName == "addAllGlobalsAsDebuggees",

              instr4.numInputs == 1, // Only the debugger instance (v3)

              instr4.input(0) == v3,

              instr4.numArguments == 0

              // The output of addAllGlobalsAsDebuggees is typically unused, so we don't check instr4.hasOutput strictly

              else { return nil }



        // If all checks passed, the contiguous sequence is confirmed.

        return i + 4 // Return the index of the last instruction in the sequence

    }

}
