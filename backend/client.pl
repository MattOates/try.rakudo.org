# This program is a simple unix socket client.  It will connect to the
# UNIX socket specified by $rendezvous.  This program is written to
# work with the UnixServer example in POE's cookbook.  While it
# touches upon several POE modules, it is not meant to be an
# exhaustive example of them.  Please consult "perldoc [module]" for
# more details.
use strict;
use warnings;
use Socket qw(AF_UNIX);
use POE;                          # For base features.
use POE::Wheel::SocketFactory;    # To create sockets.
use POE::Wheel::ReadWrite;        # To read/write lines with sockets.
use POE::Wheel::ReadLine;         # To read/write lines on the console.

# Specify a UNIX rendezvous to use.  This is the location the client
# will connect to, and it should correspond to the location a server
# is listening to.
my $rendezvous = '/tmp/poe-unix-socket';

# Create the session that will pass information between the console
# and the server.  The create() constructor maps a number of events to
# the functions that will be called to handle them.  For example, the
# "sock_connected" event will cause the socket_connected() function to
# be called.
POE::Session->create(
  inline_states => {
    _start         => \&client_init,
    sock_connected => \&socket_connected,
    sock_error     => \&socket_error,
    sock_input     => \&socket_input,
    cli_input      => \&console_input,
  },
);

# Run the client until it is finished, then exit because we're done.
# The rest of this program consists of event handlers.
$poe_kernel->run();
exit 0;

# The client_init() function is called when POE sends a "_start" event
# to the session.  This happens automatically whenever a session is
# created, and its purpose is to notify your code when it can begin
# doing things.
# Here we create the SocketFactory that will connect a socket to the
# server.  The socket factory is tightly associated with its session,
# so it is kept in the session's private storage space (its "heap").
# The socket factory is configured to emit two events: On a successful
# connection, it sends a "sock_connected" event containing the new
# socket.  On a failure, it sends "sock_error" along with information
# about the problem.
sub client_init {
  my $heap = $_[HEAP];
  $heap->{connect_wheel} = POE::Wheel::SocketFactory->new(
    SocketDomain  => AF_UNIX,
    RemoteAddress => $rendezvous,
    SuccessEvent  => 'sock_connected',
    FailureEvent  => 'sock_error',
  );
}

# socket_connected() is called when the session receives a
# "sock_connected" event.  That event is generated by the session's
# SocketFactory object when it has connected to a server.  The newly
# connected socket is passed in ARG0.
# This function discards the SocketFactory object since its purpose
# has been fulfilled.  It then creates two new objects: a ReadWrite
# wheel to talk with the socket, and a ReadLine wheel to talk with the
# console.  POE::Wheel::ReadLine was named after Term::ReadLine, by
# the way.  Once socket_connected() has set us up the wheels, it calls
# ReadLine's get() method to prompt the user for input.
sub socket_connected {
  my ($heap, $socket) = @_[HEAP, ARG0];
  delete $heap->{connect_wheel};
  $heap->{io_wheel} = POE::Wheel::ReadWrite->new(
    Handle     => $socket,
    InputEvent => 'sock_input',
    ErrorEvent => 'sock_error',
  );
  $heap->{cli_wheel} = POE::Wheel::ReadLine->new(InputEvent => 'cli_input');
  $heap->{cli_wheel}->get("=> ");
}

# socket_input() is called to handle "sock_input" events.  These
# events are provided by the POE::Wheel::ReadWrite object that was
# created in socket_connected().
# socket_input() moves information from the socket to the console.
sub socket_input {
  my ($heap, $input) = @_[HEAP, ARG0];
  $heap->{cli_wheel}->put("Server Said: $input");
}

# socket_error() is called to handle "sock_error" events.  These
# events can come from two places: The SocketFactory will send it if a
# connection fails, and the ReadWrite object will send it if a read or
# write error occurs.
# The most common way to handle I/O errors is to shut down the sockets
# having problems.  Here we'll delete all our wheels so the program
# can shut down gracefully.
# ARG0 contains the name of the syscall that failed.  It is often
# "connect" or "bind" or "read" or "write".  ARG1 and ARG2 contain the
# numeric and descriptive contents of $! at the time of the failure.
sub socket_error {
  my ($heap, $syscall, $errno, $error) = @_[HEAP, ARG0 .. ARG2];
  $error = "Normal disconnection." unless $errno;
  warn "Client socket encountered $syscall error $errno: $error\n\n";
  delete $heap->{connect_wheel};
  delete $heap->{io_wheel};
  delete $heap->{cli_wheel};
}

# Finally, the console_input() function is called to handle
# "cli_input" events.  These events are created when
# POE::Wheel::ReadLine (created in socket_connected()) receives user
# input from the console.
# Plain input is registered with ReadLine's input history, echoed back
# to the console, and sent to the server.  Exceptions, such as when
# the user presses Ctrl+C to interrupt the program, are also handled.
# POE::Wheel::ReadLine events include two parameters other than the
# usual KERNEL, HEAP, etc.  The ARG0 parameter contains plain input.
# If that's undefined, then ARG1 will contain an exception.
sub console_input {
  my ($heap, $input, $exception) = @_[HEAP, ARG0, ARG1];
  if (defined $input) {
    # $heap->{cli_wheel}->addhistory($input);
    $heap->{io_wheel}->put($input);
  }
  elsif ($exception eq 'cancel') {
    $heap->{cli_wheel}->put("Canceled.");
  }
  else {
    $heap->{cli_wheel}->put("Bye.");
    delete $heap->{cli_wheel};
    delete $heap->{io_wheel};
    return;
  }

  # Prompt for the next bit of input.
  $heap->{cli_wheel}->get("=> ");
}
