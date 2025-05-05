

// Specific mutator to transform the positive test case (recursive constructor call via getter)

// into the negative test case (avoiding the recursive call).

public class SpecificCrashMutator: BaseMutator {



    init() {

        super.init(name: "SpecificCrashMutator")

    }



    override public func mutate(_ program: Program, _ fuzzer: Fuzzer) -> Program? {

        // This mutator is highly specific and looks for the exact structure of the positive case.

        // If the structure deviates slightly, the mutation will likely fail.



        let b = fuzzer.makeBuilder()

        var foundClass = false

        var classInfo: (name: String, startIdx: Int, endIdx: Int)? = nil

        var constructorInfo: (startIdx: Int, endIdx: Int, loadPropertyIdx: Int?)? = nil

        var getterInfo: (name: String, startIdx: Int, endIdx: Int, constructIdx: Int?)? = nil

        var mainConstructIdx: Int? = nil



        // 1. Analyze the program structure to find the target pattern

        for (idx, instr) in program.code.enumerated() {

            if let op = instr.op as? BeginClassDefinition {

                if !foundClass { // Only handle the first class found for simplicity

                    foundClass = true

                    classInfo = (name: op.className, startIdx: idx, endIdx: -1)

                }

            } else if let op = instr.op as? EndClassDefinition {

                if foundClass && classInfo != nil && classInfo!.endIdx == -1 {

                    classInfo!.endIdx = idx

                }

            } else if let op = instr.op as? BeginMethodDefinition {

                if foundClass && classInfo != nil && classInfo!.endIdx == -1 { // Inside the class definition

                    if op.isConstructor {

                        constructorInfo = (startIdx: idx, endIdx: -1, loadPropertyIdx: nil)

                    } else if op.isGetter {

                        // Assuming the getter name is 'c' based on the example

                        if op.methodName == "c" {

                             getterInfo = (name: op.methodName, startIdx: idx, endIdx: -1, constructIdx: nil)

                        }

                    }

                }

            } else if let op = instr.op as? EndMethodDefinition {

                 if constructorInfo != nil && constructorInfo!.endIdx == -1 {

                     constructorInfo!.endIdx = idx

                 } else if getterInfo != nil && getterInfo!.endIdx == -1 {

                     getterInfo!.endIdx = idx

                 }

            } else if let op = instr.op as? LoadProperty {

                 // Inside constructor, look for this.c;

                 if constructorInfo != nil && constructorInfo!.endIdx == -1 && op.propertyName == "c" && instr.input(0) == b.currentScope.this {

                     constructorInfo!.loadPropertyIdx = idx

                 }

                 // Inside getter, look for access to this.constructor

                 if getterInfo != nil && getterInfo!.endIdx == -1 && op.propertyName == "constructor" && instr.input(0) == b.currentScope.this {

                     // Potential prelude to the construct call

                 }

            } else if let op = instr.op as? Construct {

                 // Inside getter, look for new this.constructor()

                 if getterInfo != nil && getterInfo!.endIdx == -1 {

                     // Check if the constructed object is based on 'this.constructor' (heuristic)

                     // A more robust check would trace the variable from LoadProperty 'constructor'

                     // For this specific case, assume any Construct inside the getter is the target

                     getterInfo!.constructIdx = idx

                 }

                 // Outside class, look for new C0()

                 if classInfo != nil && classInfo!.endIdx != -1 && idx > classInfo!.endIdx {

                      // Check if constructing the identified class

                      // A more robust check would compare the constructor variable with the class definition

                      // For this specific case, assume the first Construct after the class is the target

                      if mainConstructIdx == nil {

                           mainConstructIdx = idx

                      }

                 }

            }

            // Advance builder scope simulation to track 'this'

            b.append(instr)

        }



        // 2. Check if the full pattern was found

        guard let classInfo = classInfo, classInfo.endIdx != -1,

              let constructorInfo = constructorInfo, constructorInfo.endIdx != -1, /* constructorInfo.loadPropertyIdx != nil, */ // Relaxed: Allow construction even if this.c wasn't found

              let getterInfo = getterInfo, getterInfo.endIdx != -1, getterInfo.constructIdx != nil,

              let mainConstructIdx = mainConstructIdx else {

            // Pattern not found, cannot apply this specific mutation

            return nil

        }



        // 3. Rebuild the program with modifications

        let builder = fuzzer.makeBuilder()

        var instanceVar: Variable? = nil



        for (idx, instr) in program.code.enumerated() {

            if idx == classInfo.startIdx {

                // Begin Class

                builder.append(instr)

            } else if idx > classInfo.startIdx && idx < classInfo.endIdx {

                 // Inside Class Definition

                 if idx == constructorInfo.startIdx {

                     // Begin Constructor

                     builder.append(instr)

                     // Add: this._internal_c = undefined;

                     let thisVar = builder.currentScope.this

                     let internalC = builder.loadString("_internal_c")

                     let undefined = builder.loadUndefined()

                     builder.storeProperty(internalC, on: thisVar, as: undefined)



                 } else if idx > constructorInfo.startIdx && idx < constructorInfo.endIdx {

                     // Inside Constructor Body

                     if idx == constructorInfo.loadPropertyIdx {

                         // Skip: this.c; (the LoadProperty instruction)

                         continue

                     } else {

                         // Copy other constructor instructions

                         builder.append(instr)

                     }

                 } else if idx == constructorInfo.endIdx {

                      // End Constructor

                      builder.append(instr)



                      // Add Setter: set c(val) { this._internal_c = val; }

                      let methodName = builder.loadString("c")

                      builder.beginMethodDefinition(name: methodName, parameters: ["val"], isStatic: false, isGetter: false, isSetter: true)

                      do {

                          let thisVar = builder.currentScope.this

                          let internalC = builder.loadString("_internal_c")

                          let val = builder.findVariable(forName: "val")!

                          builder.storeProperty(internalC, on: thisVar, as: val)

                          builder.loadUndefined() // Setter should return undefined implicitly

                          builder.return()

                      }

                      builder.endMethodDefinition()



                 } else if idx == getterInfo.startIdx {

                     // Begin Getter 'c'

                     builder.append(instr)

                 } else if idx > getterInfo.startIdx && idx < getterInfo.endIdx {

                     // Inside Getter Body

                     if idx == getterInfo.constructIdx {

                         // Replace 'new this.constructor()' with alternative logic

                         // let temp_obj = { value: Math.random() };

                         // if (temp_obj.value > 0.5) { }

                         let math = builder.loadBuiltin("Math")

                         let randomFunc = builder.loadProperty("random", of: math)

                         let randomVal = builder.callFunction(randomFunc, withArgs: [])

                         let valueStr = builder.loadString("value")

                         let tempObj = builder.createObject(with: [valueStr: randomVal])



                         let objValue = builder.loadProperty(valueStr, of: tempObj)

                         let threshold = builder.loadFloat(0.5)

                         let comparison = builder.compare(objValue, with: threshold, using: .greaterThan)

                         builder.beginIf(comparison)

                         // Optional: Add some placeholder work inside the if

                         builder.loadNull() // Placeholder

                         builder.endIf()



                         // Ensure the loop remains if desired, but it's often just filler

                         // Copy the original loop for structural similarity if present nearby

                         // For simplicity here, we omit explicitly finding and copying the loop

                         // It might get copied if it comes after the Construct instruction



                         // Add: return this._internal_c;

                         let thisVar = builder.currentScope.this

                         let internalC = builder.loadString("_internal_c")

                         let backingValue = builder.loadProperty(internalC, of: thisVar)

                         builder.reassign(instr.output, to: backingValue) // Re-use original getter's output var if possible





                     } else {

                        // Skip the instruction that loaded 'this.constructor' if it was separate

                        if let loadPropOp = program.code[idx-1].op as? LoadProperty,

                           loadPropOp.propertyName == "constructor",

                           program.code[idx].op is Construct,

                           program.code[idx].input(0) == program.code[idx-1].output {

                               // This instruction loaded the constructor for the subsequent Construct

                               // Skip it as we replaced the Construct

                               continue

                           }





                         // Copy other getter instructions

                         // Caution: If the original loop was *before* the Construct, it's copied here.

                         // If it was *after*, it will be copied below.

                         builder.append(instr)

                     }

                 } else if idx == getterInfo.endIdx {

                     // Before ending the getter, ensure it returns the backing field

                     // Check if the last instruction before EndMethodDefinition was a Return

                     var needsReturn = true

                     if let lastOp = builder.lastInstruction?.op {

                         if lastOp is Return {

                             needsReturn = false

                         }

                     }



                     if needsReturn {

                         let thisVar = builder.currentScope.this

                         let internalC = builder.loadString("_internal_c")

                         let backingValue = builder.loadProperty(internalC, of: thisVar)

                         builder.return(backingValue)

                     }



                     // End Getter

                     builder.append(instr)

                 } else {

                     // Copy other class elements (e.g., other methods)

                     builder.append(instr)

                 }



            } else if idx == classInfo.endIdx {

                 // End Class

                 builder.append(instr)

            } else if idx == mainConstructIdx {

                 // The original 'new C0(C0)'

                 // Replicate it but capture the instance

                 instanceVar = builder.adopt(instr.output) // Get the variable for the instance

                 builder.append(instr) // Execute the construction



                 // Add loop: for (let i = 0; i < 100; i++) { instance.c; }

                 guard let instance = instanceVar else { return nil } // Should exist



                 let i = builder.loadInt(0)

                 builder.beginForLoop(i, .lessThan, builder.loadInt(100), .Add, builder.loadInt(1)) { _ in

                     let cProp = builder.loadString("c")

                     builder.loadProperty(cProp, of: instance) // Access the getter

                 }

            } else if idx > classInfo.endIdx && mainConstructIdx != nil && idx > mainConstructIdx {

                 // Copy instructions after the main construction

                 builder.append(instr)

            } else if idx < classInfo.startIdx {

                 // Copy instructions before the class definition

                 builder.append(instr)

            } else {

                 // Should not happen based on initial checks, but copy defensively

                 builder.append(instr)

            }

        }





        // Check if an instance was created and assigned

        guard instanceVar != nil else {

             // The main construction step failed to be processed correctly

             return nil

        }



        return builder.finalize()

    }

}
