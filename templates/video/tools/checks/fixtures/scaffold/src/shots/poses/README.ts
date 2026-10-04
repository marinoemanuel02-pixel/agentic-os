// One file per shot, named after its id (S01.ts), authored after the framing is reviewed:
//   export const poses = {start: {pos: [x, y, z], target: [x, y, z], fov: 30}, end: {...}};
// Only that shot's module imports it, so a pose edit re-renders one shot. No example film poses are shipped.
