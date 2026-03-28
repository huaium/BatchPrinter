# Style and Conventions
- Language: Swift + SwiftUI on macOS.
- Naming: Types use PascalCase, methods/properties use camelCase, enum cases use lowerCamelCase.
- Architecture: view-model centric (`MainViewModel`) with services for side effects.
- Concurrency: async work often done via `Task.detached` and coordinated back on `@MainActor` view model.
- Error handling: user-visible errors via `lastErrorMessage`; operational details logged to `logStore`.
- UI pattern: action buttons + disabled-state guards; dialogs/popovers for advanced options/help.
- Data flow: `@Published` state in view model consumed by SwiftUI bindings.