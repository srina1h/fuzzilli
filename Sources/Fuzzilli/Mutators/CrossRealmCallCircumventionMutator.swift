

/// A mutator that attempts to circumvent crashes related to cross-realm calls

/// involving callbacks defined in the caller's realm.

///

/// Specifically, it targets patterns like:

/// ```javascript

/// function outer(realmParam) {

///     // Method from realmParam's prototype called via .call

///     // 'this' is from the current realm

///     // Callback is from the current realm

///     realmParam.SomeClass.prototype.someMethod.call([1, 2, 3], () => { /* uses current realm vars */ });

/// }

/// outer(newGlobal());

/// ```

/// It transforms this into:

/// ```javascript

/// function outer(realmParam) {

///     // Define a compatible callback *inside* realmParam

///     realmParam.eval("function cb(a, b) { /* simple implementation */ }");

///     try {

///         // Call the method using the callback from realmParam

///         realmParam.SomeClass.prototype.someMethod.call([1, 2, 3], realmParam.cb);

///     } catch (e) {}

/// }

/// outer(newGlobal());

/// ```

public class CrossRealmCallCircumventionMutator: BaseInstructionMutator {

    private let logger = Logger(withLabel: "CrossRealmCallCircumventionMutator")



    public init() {

        super.init(name: "CrossRealmCallCircumventionMutator", maxSimultaneousMutations: 1)

    }



    public override func canMutate(_ instr: Instruction) -> Bool {

        // Check if it's obj.method.call(...) or obj.method.apply(...)

        guard instr.op is CallMethod,

              (instr.methodName == "call" || instr.methodName == "apply") else {

            return false

        }

        // Needs at least 3 inputs:

        // 1. The method being called (e.g., realmParam.Array.prototype.toSorted)

        // 2. The 'this' argument for .call/.apply

        // 3. At least one argument for the target method (which we expect to be the problematic callback)

        guard instr.numInputs >= 3 else {

            return false

        }



        // Further checks are deferred to mutate() as they require ProgramBuilder access.

        return true

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        // --- Detailed Verification using ProgramBuilder ---



        // 1. Verify 'this' argument (input 1) likely comes from the current realm

        let thisVar = instr.input(1)

        guard let thisDef = b.definition(of: thisVar),

              (thisDef.op is CreateObject || thisDef.op is CreateArray || thisDef.op is LoadInteger || thisDef.op is LoadFloat || thisDef.op is LoadString) else {

            logger.verbose("Skipping: 'this' argument \(thisVar) is not a simple literal.")

            b.adopt(instr) // Keep original instruction

            return

        }



        // 2. Find an argument to the *target* method that is a function defined in the current scope

        let callArgs = instr.inputs // [methodVar, thisVar, arg1, arg2, ...]

        let targetMethodArgs = Array(callArgs.dropFirst(2)) // [arg1, arg2, ...]



        var originalCallbackVar: Variable? = nil

        var originalCallbackArgIndex: Int = -1 // Index within targetMethodArgs



        for (idx, argVar) in targetMethodArgs.enumerated() {

            if let argDef = b.definition(of: argVar), argDef.op is BeginAnyFunction {

                originalCallbackVar = argVar

                originalCallbackArgIndex = idx

                break

            }

        }



        guard let originalCallbackVar = originalCallbackVar else {

            logger.verbose("Skipping: Could not find a function argument for the target method.")

            b.adopt(instr)

            return

        }



        // 3. Trace back the method variable (input 0) to find the likely global object parameter

        let methodVar = instr.input(0)

        var currentVar = methodVar

        var globalVar: Variable? = nil

        var depth = 0

        let maxDepth = 5 // Limit search depth



        while depth < maxDepth {

            guard let def = b.definition(of: currentVar) else { break }



            if def.op is LoadProperty || def.op is LoadElement {

                guard def.numInputs > 0 else { break }

                currentVar = def.input(0) // Move to the base object

                // Heuristic: If the base is a parameter of the current function, assume it's our target global

                if b.currentFunction.parameters.contains(currentVar) {

                    globalVar = currentVar

                    break

                }

            } else if def.op is LoadParameter {

                 // If we hit a parameter directly, assume it's the target global

                 // (More likely to happen if the method itself was passed in, less common)

                 // Let's prioritize the check above (base is parameter).

                 // If the above check hasn't found it, and this is param 0, maybe take it?

                 if b.currentFunction.parameters.first == currentVar {

                    globalVar = currentVar

                    break

                 }

                 break // Don't trace beyond LoadParameter otherwise

            } else {

                break // Stop if we hit something else

            }

            depth += 1

        }



        guard let globalVar = globalVar else {

            logger.verbose("Skipping: Could not trace method variable \(methodVar) back to a function parameter.")

            b.adopt(instr)

            return

        }



        logger.verbose("Applying circumvention: global=\(globalVar), method=\(methodVar), this=\(thisVar), callback=\(originalCallbackVar)")



        // --- Transformation ---



        // 4. Define a simple callback function inside the target realm using eval

        //    Use a somewhat unique name to reduce collision chances.

        let callbackName = "fuzzilli_compareFn_\(Int.random(in: 0..<1000))"

        // TODO: Adapt the signature based on the original callback? For now, assume a comparator.

        let evalString = "function \(callbackName)(a, b) { try { return a < b ? -1 : (a > b ? 1 : 0); } catch { return 0; } }"

        let evalStringVar = b.loadString(evalString)

        b.callMethod(globalVar, methodName: "eval", args: [evalStringVar]) // Insert before the original call



        // 5. Load the newly defined function from the target realm

        let newCallbackVar = b.loadProperty(globalVar, callbackName)



        // 6. Prepare arguments for the new .call/.apply within a try-catch block

        var newTargetMethodArgs = targetMethodArgs

        newTargetMethodArgs[originalCallbackArgIndex] = newCallbackVar // Replace original callback



        var newCallArgs: [Variable] = [thisVar] // Start with 'this' arg

        if instr.methodName == "call" {

            newCallArgs.append(contentsOf: newTargetMethodArgs)

        } else { // instr.methodName == "apply"

            // For apply, the arguments need to be in an array

            let argsArrayVar = b.createArray(with: newTargetMethodArgs)

            newCallArgs.append(argsArrayVar)

        }



        // 7. Replace the original instruction with the try-catch block calling the method

        let outputVar = instr.output // Preserve output variable



        b.beginTry()

        if instr.hasOutput {

            b.callMethod(methodVar, methodName: instr.methodName!, args: newCallArgs, output: outputVar)

        } else {

            b.callMethod(methodVar, methodName: instr.methodName!, args: newCallArgs)

        }

        b.beginCatch()

        // Optional: Add a dummy operation or comment inside catch

        // b.loadString("Caught exception in cross-realm circumvention block")

        // Or just leave it empty

        let exceptionVar = b.catchException()

        b.nop(input: exceptionVar) // Consume the exception variable

        b.endCatch()



        // The original instruction `instr` is implicitly replaced as we built new instructions

        // and didn't call b.adopt(instr).

    }

}
