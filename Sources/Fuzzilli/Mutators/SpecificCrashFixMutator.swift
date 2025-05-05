import Foundation



/// A highly specialized mutator designed to transform a specific crashing pattern

/// related to 'arguments' object usage, '||' operator shortcutting with function calls,

/// and potentially infinite loops into a non-crashing variant based on a known fix.

///

/// This mutator specifically targets the pattern observed in the provided test case:

/// 1. A function (`uceFault`) returning `arguments`.

/// 2. A caller (`f85`) assigning `obj = (uceFault(...) || uceFault)`.

/// 3. A loop (`for (...; max; ...)`) potentially running indefinitely.

///

/// It attempts to rebuild the program structure applying these fixes:

/// 1. Modify `uceFault` to return a simple value (e.g., `param + 1` or `null`) instead of `arguments`.

/// 2. Modify `f85` to use an explicit `if` check instead of `||` for the assignment to `obj`.

/// 3. Modify the loop condition to be finite (e.g., `i < max`).

/// 4. Wrap the call inside the loop body with a `try-catch`.

///

/// NOTE: This mutator relies on heuristic detection of the pattern. A robust implementation

/// would require more sophisticated FuzzIL analysis to accurately identify the target

/// structures and variables.

public class SpecificCrashFixMutator: Mutator {



    let logger = Logger(withLabel: "SpecificCrashFixMutator")



    public init() {

        super.init(name: "SpecificCrashFixMutator")

    }



    /// Heuristic analysis result structure.

    private struct PatternInfo {

        let uceFaultFuncDefInstr: Instruction // BeginFunctionDefinition for uceFault

        let uceFaultVar: Variable           // Variable holding the uceFault function

        let uceFaultParamVar: Variable      // Variable for the parameter 'j29' in uceFault



        let f85FuncDefInstr: Instruction    // BeginFunctionDefinition for f85

        let f85Var: Variable                // Variable holding the f85 function

        let f85ParamVar: Variable           // Variable for the parameter 'j29' in f85

        let objVarInsideF85: Variable       // Variable for 'obj' inside f85 scope

        let i96VarInsideF85: Variable?      // Variable for 'i96' if found



        let loopStartInstr: Instruction     // BeginFor/While instruction

        let loopCounterVar: Variable        // Variable for 'j29' used as loop counter

        let loopConditionVar: Variable      // Variable 'max' used in the original loop condition

        let loopBodyCallInstrIndex: Int     // Index of the f85 call inside the loop body



        // Add indices or instruction references if needed for replacement/rebuilding logic

    }



    /// Placeholder function for detecting the specific pattern in FuzzIL.

    /// In a real scenario, this needs detailed analysis of the instruction stream.

    private func findSpecificCrashPattern(_ program: Program) -> PatternInfo? {

        // TODO: Implement actual FuzzIL analysis to find the pattern.

        // This would involve iterating through instructions, identifying function definitions,

        // checking for `LoadArguments`, `Return`, specific call patterns, `||` logic (often involves BranchIf),

        // and loop structures with constant conditions.



        // Example Heuristic Checks (Simplified - Unlikely to be robust):

        var uceFaultInfo: (Instruction, Variable, Variable)? = nil

        var f85Info: (Instruction, Variable, Variable, Variable, Variable?)? = nil

        var loopInfo: (Instruction, Variable, Variable, Int)? = nil



        var functionDefs = [Variable: (defInstr: Instruction, paramVar: Variable?)]()

        var functionReturnsArguments = [Variable: Bool]()

        var f85Candidates = [(defInstr: Instruction, f85Var: Variable, paramVar: Variable, objVar: Variable?, i96Var: Variable?)]()



        // First pass: Identify functions and basic properties

        for instr in program.code {

            if instr.op is BeginAnyFunctionDefinition {

                 // Assume single parameter for simplicity

                 let funcVar = instr.output

                 let paramVar = instr.innerOutputs.first // Parameter variable

                 functionDefs[funcVar] = (instr, paramVar)

                 functionReturnsArguments[funcVar] = false

            } else if instr.op is LoadArguments {

                 if let currentFuncVar = program.scopes.currentFunction {

                     functionReturnsArguments[currentFuncVar] = true

                 }

            }

        }



        // Second pass: Identify pattern details

        var potentialObjVar: Variable? = nil

        var potentialI96Var: Variable? = nil

        var potentialLoopCounter: Variable? = nil

        var potentialMaxVar: Variable? = nil

        var f85CallIndexInLoop: Int? = nil



        for (idx, instr) in program.code.enumerated() {

            // Check for f85-like pattern

            if instr.op is BeginAnyFunctionDefinition {

                let f85CandidateVar = instr.output

                if let (defInstr, paramVar) = functionDefs[f85CandidateVar], let paramVar = paramVar {

                    // Look inside this function for the `obj = (uceFault || ...)` pattern

                    // Requires analyzing the function body's FuzzIL - complex

                    // Also look for Math.pow call assigned to i96

                    // Placeholder: Assume we found it and identified objVar and i96Var

                    potentialObjVar = Variable(number: 100) // Dummy var

                    potentialI96Var = Variable(number: 101) // Dummy var

                    f85Candidates.append((defInstr: defInstr, f85Var: f85CandidateVar, paramVar: paramVar, objVar: potentialObjVar, i96Var: potentialI96Var))

                }

            }



             // Check for loop pattern `for (j29=0; max; ++j29)`

             if instr.op is BeginFor || instr.op is BeginWhile { // Identify loop start

                 // Analyze loop condition: look for LoadVariable('max'), Branch based on it.

                 // Analyze updates: Look for UnaryOperation '++' on 'j29'.

                 // Placeholder: Assume we found the loop and vars

                 potentialLoopCounter = Variable(number: 200) // Dummy 'j29'

                 potentialMaxVar = Variable(number: 201) // Dummy 'max'



                 // Find the call to f85 within the loop body

                 // Requires searching between BeginFor/EndFor or BeginWhile/EndWhile

                 f85CallIndexInLoop = idx + 2 // Dummy index



                 // Assume this is our loop

                 loopInfo = (instr, potentialLoopCounter!, potentialMaxVar!, f85CallIndexInLoop!)

             }

        }





        // Match findings: Find a function that returns arguments, call it uceFault

        for (funcVar, returnsArgs) in functionReturnsArguments {

            if returnsArgs, let (defInstr, paramVar) = functionDefs[funcVar], let paramVar = paramVar {

                uceFaultInfo = (defInstr, funcVar, paramVar)

                break // Found one candidate

            }

        }



        // Match findings: Find an f85 candidate (needs check that it calls uceFault)

        if !f85Candidates.isEmpty, let objVar = potentialObjVar {

            // TODO: Add check if f85Candidates[0] actually calls uceFaultInfo?.1

            f85Info = (f85Candidates[0].defInstr, f85Candidates[0].f85Var, f85Candidates[0].paramVar, objVar, f85Candidates[0].i96Var)

        }





        // If all parts are found, construct PatternInfo

        if let uceFault = uceFaultInfo, let f85 = f85Info, let loop = loopInfo {

             logger.info("Heuristically detected specific crash pattern")

            return PatternInfo(

                uceFaultFuncDefInstr: uceFault.0, uceFaultVar: uceFault.1, uceFaultParamVar: uceFault.2,

                f85FuncDefInstr: f85.0, f85Var: f85.1, f85ParamVar: f85.2, objVarInsideF85: f85.3, i96VarInsideF85: f85.4,

                loopStartInstr: loop.0, loopCounterVar: loop.1, loopConditionVar: loop.2, loopBodyCallInstrIndex: loop.3

            )

        }



        return nil // Pattern not detected

    }





    public override func mutate(_ program: Program, using fuzzer: Fuzzer) -> Program? {

        guard let patternInfo = findSpecificCrashPattern(program) else {

            return nil // Pattern not found

        }



        let b = ProgramBuilder(for: fuzzer)

        logger.info("Rebuilding program to apply specific crash fix")



        // Keep track of original variable names if possible (for readability)

        var varNames = [Variable: String]()

        program.variables.forEach { varNames[$0] = program.name(of: $0) }

        func name(_ v: Variable) -> String? { return varNames[v] }



        // 1. Define fixed uceFault

        let uceFaultFunc = b.adopt(patternInfo.uceFaultVar, naming: name(patternInfo.uceFaultVar) ?? "uceFault")

        b.definePlainFunction(withSignature: [.plain(patternInfo.uceFaultParamVar)], isJSStrictMode: false) { args in

            let j29 = b.adopt(args[0], naming: name(patternInfo.uceFaultParamVar) ?? "j29") // Use original param var



            // if (j29) return j29 + 1; return null;

            let v1 = b.loadInt(1)

            let sum = b.binary(j29, v1, with: .Add)

            // Condition: Check truthiness - comparing with 0 is one way

            let isTruthy = b.compare(j29, b.loadInt(0), with: .notEqual)



            b.buildIfElse(isTruthy, ifBody: {

                b.doReturn(sum)

            }, elseBody: {

                b.doReturn(b.loadNull())

            })

        }

        b.reassign(uceFaultFunc, to: b.outputs.last!) // Assign the function object



        // 2. Define fixed f85

        let f85Func = b.adopt(patternInfo.f85Var, naming: name(patternInfo.f85Var) ?? "f85")

        let objVar = b.adopt(patternInfo.objVarInsideF85, naming: name(patternInfo.objVarInsideF85) ?? "obj")

        let i96Var = b.adopt(patternInfo.i96VarInsideF85 ?? b.genVar(), naming: name(patternInfo.i96VarInsideF85 ?? Variable(number: 0)) ?? "i96") // Adopt or gen new



        b.definePlainFunction(withSignature: [.plain(patternInfo.f85ParamVar)], isJSStrictMode: false) { args in

            let j29 = b.adopt(args[0], naming: name(patternInfo.f85ParamVar) ?? "j29_f85") // Use original param var



            // i96 = Math.pow(2, j29);

            let v2 = b.loadInt(2)

            let math = b.loadBuiltin("Math")

            let pow = b.getProperty(math, "pow")

            let powResult = b.callFunction(pow, withArgs: [v2, j29])

            b.reassign(i96Var, to: powResult) // Assign to i96



            // obj = uceFault(j29);

            let callResult = b.callFunction(uceFaultFunc, withArgs: [j29])

            b.reassign(objVar, to: callResult)



            // if (!obj) { obj = uceFault; }

            // Check for falsiness (e.g., compare with null, undefined, 0, false, "")

            // A simple truthiness check with BranchIfFalse works well here.

            b.buildIf(objVar, invert: true) { // If obj is falsy

                 b.reassign(objVar, to: uceFaultFunc) // Assign the function itself

            }

        }

        b.reassign(f85Func, to: b.outputs.last!) // Assign the function object



        // 3. Define max and the fixed loop

        let maxVar = b.adopt(patternInfo.loopConditionVar, naming: name(patternInfo.loopConditionVar) ?? "max")

        let loopCounterVar = b.adopt(patternInfo.loopCounterVar, naming: name(patternInfo.loopCounterVar) ?? "j29_loop")



        let maxLiteral = b.loadInt(150) // Assign max = 150

        b.reassign(maxVar, to: maxLiteral)



        let initialCounter = b.loadInt(0) // j29 = 0

        b.reassign(loopCounterVar, to: initialCounter)



        // for (j29 = 0; j29 < max; ++j29)

        let v1_loop = b.loadInt(1) // For increment

        b.buildForLoop(loopCounterVar, .lessThan, maxVar, .Add, v1_loop) { // Correct condition: j29 < max

            // try { f85(j29); } catch(e) {}

            b.buildTryCatchFinally(tryBody: {

                _ = b.callFunction(f85Func, withArgs: [loopCounterVar]) // Call f85, ignore result

            }, catchBody: { _ in

                b.nop() // Empty catch needs at least one instruction

            })

        }



        // 4. Optional: Add commented log line using PlainJS (might not always be safe/desirable)

        // b.eval("// console.log(\"Loop finished without crashing.\");", hasOutput: false)



        // Finalize and validate the new program

        let newProgram = b.finalize()

        guard newProgram.check() == .valid else {

            logger.error("SpecificCrashFixMutator generated an invalid program.")

            // Maybe return the original program or nil? Returning nil is standard for failed mutations.

            return nil

        }



        // Ensure the mutation actually changed the code significantly

        guard !program.isSemanticallyEquivalent(to: newProgram) else {

             logger.info("SpecificCrashFixMutator resulted in semantically equivalent program.")

             return nil

         }





        logger.info("Successfully generated fixed program.")

        return newProgram

    }

}
