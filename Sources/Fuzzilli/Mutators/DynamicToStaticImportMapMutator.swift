

/// A mutator that replaces dynamically created import maps with static ones

/// to circumvent potential race conditions during module loading.

///

/// It targets the following pattern:

/// ```javascript

/// // Script 1 (in head)

/// (function () {

///     const script = document.createElement('script');

///     script.type = 'importmap';

///     script.textContent = '{}'; // or some valid JSON

///     document.head.appendChild(script);

/// }());

/// // Script 2 (in body or later)

/// <script src="module.js" type="module"></script>

/// ```

/// And replaces the dynamic creation part with:

/// ```html

/// <!-- In head -->

/// <script type="importmap">

/// {

///     "imports": {}

/// }

/// </script>

/// ```

public class DynamicToStaticImportMapMutator: BaseProgramMutator {



    public init() {

        super.init(name: "DynamicToStaticImportMapMutator")

    }



    override public func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Program? {

        var foundPattern = false

        var dynamicImportMapCreationIndices: [Int] = []

        var dynamicScriptVar: Variable? = nil

        var headAppendIndex: Int = -1

        var headVar: Variable? = nil

        var createScriptIndex = -1

        var setTypeIndex = -1

        var setContentIndex = -1

        var getHeadIndex = -1



        // Scan for the dynamic import map pattern

        for (i, instr) in program.enumerated() {

            // 1. Find createElement('script')

            if instr.op is CreateElement, instr.hasStringAttribute("script"), instr.numOutputs == 1 {

                // Start of potential pattern

                dynamicScriptVar = instr.output

                createScriptIndex = i

                // Reset other indices

                setTypeIndex = -1

                setContentIndex = -1

                getHeadIndex = -1

                headAppendIndex = -1

                headVar = nil

                continue

            }



            guard let currentScriptVar = dynamicScriptVar else { continue }



            // 2. Find script.type = 'importmap'

            if instr.op is SetElementProperty,

               instr.numInputs >= 2,

               instr.input(0) == currentScriptVar,

               instr.op.attributes.contains(.stringAttr("type")), // Check property name

               program.lookupInstr(forVariable: instr.input(1))?.op is LoadString, // Check value source

               (program.lookupInstr(forVariable: instr.input(1))?.op as? LoadString)?.value == "importmap" { // Check value

                setTypeIndex = i

                continue

            }



            // 3. Find script.textContent = '{...}'

            if instr.op is SetElementProperty,

               instr.numInputs >= 2,

               instr.input(0) == currentScriptVar,

               instr.op.attributes.contains(.stringAttr("textContent")) { // Check property name

                 // We don't strictly need to check the content, just the structure

                 // Check if input 1 is a LoadString? Could be more complex JSON building.

                 // Accepting any SetElementProperty 'textContent' on the script var for now.

                 setContentIndex = i

                 continue

            }





            // 4. Find document.head

            // This might happen before or after setting properties

            if instr.op is GetDocumentHead, instr.numOutputs == 1 {

                headVar = instr.output

                getHeadIndex = i

                continue

            }



            // 5. Find head.appendChild(script)

            if let currentHeadVar = headVar,

               instr.op is AppendChild,

               instr.numInputs == 2,

               instr.input(0) == currentHeadVar,

               instr.input(1) == currentScriptVar {

                headAppendIndex = i



                // Check if all parts are found

                if createScriptIndex != -1 && setTypeIndex != -1 && setContentIndex != -1 && getHeadIndex != -1 && headAppendIndex != -1 {

                    dynamicImportMapCreationIndices = [createScriptIndex, setTypeIndex, setContentIndex, getHeadIndex, headAppendIndex]

                    foundPattern = true

                    break // Found one instance, stop searching

                } else {

                     // Reset if appendChild is found but other parts are missing (unlikely state, but safety)

                     dynamicScriptVar = nil

                }

            }

        }





        // If the full pattern was found, perform the replacement

        if foundPattern {

            let newBuilder = fuzzer.makeBuilder()

            var insertedStaticMap = false



            // Determine insertion point - ideally early, after imports/program setup, before body generation

            // Heuristic: Try to insert after the first few instructions, or specifically after head is obtained if possible.

            // Let's try inserting around the original GetDocumentHead location if found, otherwise early.

            let insertionPoint = (getHeadIndex != -1) ? (getHeadIndex + 1) : 1 // Insert after GetDocumentHead or at index 1



            for i in 0..<program.size {

                // Skip the instructions identified as part of the dynamic creation pattern

                if dynamicImportMapCreationIndices.contains(i) {

                    continue

                }



                // Insert the static import map at the chosen point

                if i == insertionPoint {

                    newBuilder.beginHTMLElement(tagName: "script")

                    newBuilder.setAttribute(name: "type", value: "importmap")

                    // Fuzzilli typically uses LoadString then SetElementProperty/AddElementContent

                    let mapContent = """

                    {

                        "imports": {}

                    }

                    """

                    let contentVar = newBuilder.loadString(mapContent)

                    // Use SetElementProperty textContent - requires implicit element access or explicit var

                    // If BeginHTMLElement implicitly sets a current element context:

                     newBuilder.setElementProperty(propertyName: "textContent", value: contentVar)

                    // Or if BeginHTMLElement returns the element:

                    // let staticScriptVar = newBuilder.beginHTMLElement(tagName: "script")

                    // newBuilder.setAttribute(element: staticScriptVar, name: "type", value: "importmap")

                    // ... load string ...

                    // newBuilder.setElementProperty(element: staticScriptVar, propertyName: "textContent", value: contentVar)

                    // Assuming the first variant for now

                    newBuilder.endHTMLElement()

                    insertedStaticMap = true

                }



                // Adopt the current instruction from the original program

                newBuilder.adopt(program.instruction(i))

            }



            // If insertion point was beyond the end (e.g., empty program?), insert now.

            if !insertedStaticMap {

                 newBuilder.beginHTMLElement(tagName: "script")

                 newBuilder.setAttribute(name: "type", value: "importmap")

                 let mapContent = """

                 {

                     "imports": {}

                 }

                 """

                 let contentVar = newBuilder.loadString(mapContent)

                 newBuilder.setElementProperty(propertyName: "textContent", value: contentVar)

                 newBuilder.endHTMLElement()

                 insertedStaticMap = true

            }





            // Only return if we actually inserted the map

            if insertedStaticMap {

                return newBuilder.finalize()

            } else {

                // Should not happen if pattern was found, but safety check.

                 return nil

            }



        } else {

            // Pattern not found, mutation did not apply

            return nil

        }

    }

}



// Helper extensions (potentially adapted from or added to Fuzzilli utils)



// Placeholder for a way to check Operation attributes.

// Real implementation depends on Fuzzilli's Operation definition.

fileprivate extension Operation {

    struct Attributes: OptionSet {

        let rawValue: Int

        static let stringAttrKey = Attributes(rawValue: 1 << 0) // Example

        // Add other attribute types if needed



        // Helper to create an attribute instance storing a string value

        // This structure needs alignment with Fuzzilli's actual implementation

        static func stringAttr(_ value: String) -> OperationAttributeContainer {

             return OperationAttributeContainer(key: .stringAttrKey, value: value)

        }

    }



    // Simplified check - assumes attributes are stored in a way that allows this check

    // In real Fuzzilli, this might involve checking op properties or metadata.

     var attributes: Set<OperationAttributeContainer> {

        var attrs = Set<OperationAttributeContainer>()

        if let op = self as? SetElementProperty {

            attrs.insert(.stringAttr(op.propertyName))

        } else if let op = self as? SetAttribute {

            attrs.insert(.stringAttr(op.attributeName))

        }

        // Add more ops as needed

        return attrs

    }

}



// Placeholder struct to associate a key (like propertyName) with its value

// Needs to match how Fuzzilli stores operation metadata.

fileprivate struct OperationAttributeContainer: Hashable {

     let key: Operation.Attributes // e.g., signifies 'propertyName' or 'tagName'

     let value: String           // e.g., 'type', 'textContent', 'script'

}



// Helper on Instruction for easier attribute checking

fileprivate extension Instruction {

    // Check if the operation associated with this instruction has a string attribute matching the value.

    func hasStringAttribute(_ value: String) -> Bool {

        if let op = self.op as? CreateElement {

             return op.tagName == value // Assuming CreateElement has a tagName property

        }

        // Other checks might be needed depending on how attributes are stored for different Ops

        return false // Default false

    }



    // Simplified check for string property/attribute names stored in the operation itself.

    func hasOperationStringAttribute(_ value: String) -> Bool {

         return self.op.attributes.contains(.stringAttr(value))

    }

}



// Assume these operations exist in Fuzzilli with these properties/initializers

// Placeholders for actual Fuzzilli operations:

// final class CreateElement: Operation { let tagName: String; ... }

// final class SetElementProperty: Operation { let propertyName: String; ... }

// final class SetAttribute: Operation { let attributeName: String; ... }

// final class LoadString: Operation { let value: String; ... }

// final class AppendChild: Operation { ... }

// final class GetDocumentHead: Operation { ... }

// final class BeginHTMLElement: Operation { let tagName: String; ... } // May or may not return the element var

// final class EndHTMLElement: Operation { ... }

// final class AddElementContent: Operation { ... } // Alternative to SetElementProperty



// Placeholder extensions for Program to simplify value lookup

fileprivate extension Program {

    func lookupInstr(forVariable variable: Variable) -> Instruction? {

        // Search backwards from the current instruction's perspective if available,

        // or search the whole program for the instruction defining the variable.

        // This is a simplified lookup.

        for instr in self.code {

            if instr.outputs.contains(variable) || instr.innerOutputs.contains(variable) {

                return instr

            }

        }

        return nil

    }

}



// Add necessary Fuzzilli imports if this file is separate

// import Fuzzilli // Assumed to be present at the top
