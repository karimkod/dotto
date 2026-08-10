// Route observer, so a screen can tell when it has been uncovered again.
//
// The menu cannot use the pushed route's future for this: winning a level takes
// the player to the next one with pushReplacement, which completes the future of
// the route it replaces immediately. The menu would be told "you are back" while
// the player is still several levels deep, and then never told again.

import 'package:flutter/widgets.dart';

final RouteObserver<PageRoute<dynamic>> routeObserver =
    RouteObserver<PageRoute<dynamic>>();
