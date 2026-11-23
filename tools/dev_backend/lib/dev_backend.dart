/// An in-memory backend that speaks the mobile_tasks contract, to run the
/// app on the simulator without a real server (chapter 35). For
/// development only: it listens on the local interface, keeps everything
/// in memory, and forgets everything when it stops.
library;

export 'src/dev_backend_state.dart' show DevBackendState, DevRejection;
export 'src/api_port.dart' show ApiPort;
export 'src/control_handler.dart' show controlHandler;
export 'src/dev_backend_handler.dart' show devBackendHandler;
