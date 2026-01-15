# Doodle Journal Tasks

## MVP
- [x] Set deployment target to iOS 17.0 (`doodledo/doodledo.xcodeproj/project.pbxproj`)
- [x] Scaffold data model + in-memory store (`doodledo/doodledo/DoodleStore.swift`)
- [x] Build home grid shell (2-column) with empty state (`doodledo/doodledo/HomeView.swift`)
- [x] Add PencilKit canvas wrapper (`doodledo/doodledo/DrawingCanvasView.swift`)
- [x] Wire canvas screen + navigation (`doodledo/doodledo/CanvasView.swift`, `doodledo/doodledo/ContentView.swift`)
- [x] Add core entry-store tests via Swift package (`doodledo/DoodleCore`)

## Next
- [ ] Persist drawings to disk and load on launch (`doodledo/doodledo/DoodleStore.swift`)
- [ ] Wire app store to `DoodleCore` package for shared entry logic (`doodledo/doodledo/DoodleStore.swift`)
- [ ] Generate and cache thumbnails on save (`doodledo/doodledo/DoodleStore.swift`)
- [ ] Implement delete flow from home grid (`doodledo/doodledo/HomeView.swift`, `doodledo/doodledo/DoodleStore.swift`)
- [ ] Add undo/redo + brush size/color controls (`doodledo/doodledo/CanvasView.swift`)
- [ ] Export to PNG/JPG via share sheet (`doodledo/doodledo/CanvasView.swift`)
- [ ] Add app icon and launch screen polish (`doodledo/doodledo/Assets.xcassets`)
- [ ] UI polish: grid spacing, card styles, haptics (`doodledo/doodledo/HomeView.swift`, `doodledo/doodledo/CanvasView.swift`)
