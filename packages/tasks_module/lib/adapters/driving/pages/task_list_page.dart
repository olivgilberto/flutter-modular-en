import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../bloc/task_list_bloc.dart';
import '../views/task_list_view.dart';

/// The entry point of the `tasks.list` route: gets a new Bloc and hands it
/// to the View. The Pages are the only points on the driving side that look
/// up `get_it`.
final class TaskListPage extends StatelessWidget {
  const TaskListPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider<TaskListBloc>(
    create: (_) => GetIt.instance<TaskListBloc>()..add(const TaskListStarted()),
    child: const TaskListView(),
  );
}
