import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/activity_card.dart';
import 'package:opennutritracker/core/presentation/widgets/placeholder_card.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_activity/presentation/add_activity_screen.dart';
import 'package:opennutritracker/features/home/presentation/widgets/share_activity_qr_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

enum _ActivityPopupMenuSelection { onCopy, onShare, onImport }

class ActivityVerticalList extends StatefulWidget {
  final DateTime day;
  final String title;
  final List<UserActivityEntity> userActivityList;
  final Function(BuildContext, UserActivityEntity) onItemLongPressedCallback;
  final Function(BuildContext, UserActivityEntity)? onItemTappedCallback;
  final Function(bool isDragging)? onItemDragCallback;
  final Function(UserActivityEntity)? onCopyActivityCallback;
  final double? polarActiveKcal;

  const ActivityVerticalList({
    super.key,
    required this.day,
    required this.title,
    required this.userActivityList,
    required this.onItemLongPressedCallback,
    this.onItemTappedCallback,
    this.onItemDragCallback,
    this.onCopyActivityCallback,
    this.polarActiveKcal,
  });

  @override
  State<ActivityVerticalList> createState() => _ActivityVerticalListState();
}

class _ActivityVerticalListState extends State<ActivityVerticalList> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Icon(
                UserActivityEntity.getIconData(),
                size: 24,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              const SizedBox(width: 4.0),
              Text(
                widget.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
              ),
              const Spacer(),
              PopupMenuButton<_ActivityPopupMenuSelection>(
                onSelected: (_ActivityPopupMenuSelection selection) async {
                  switch (selection) {
                    case _ActivityPopupMenuSelection.onCopy:
                      for (final activity in widget.userActivityList) {
                        widget.onCopyActivityCallback!(activity);
                      }
                    case _ActivityPopupMenuSelection.onShare:
                      if (context.mounted) {
                        await showDialog(
                          context: context,
                          builder: (_) => ShareActivityQrDialog(
                            activityList: widget.userActivityList,
                          ),
                        );
                      }
                    case _ActivityPopupMenuSelection.onImport:
                      if (context.mounted) {
                        Navigator.of(context).pushNamed(
                          NavigationOptions.importActivityScannerRoute,
                        );
                      }
                  }
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<_ActivityPopupMenuSelection>>[
                  if (widget.onCopyActivityCallback != null &&
                      widget.userActivityList.isNotEmpty)
                    PopupMenuItem<_ActivityPopupMenuSelection>(
                      value: _ActivityPopupMenuSelection.onCopy,
                      child: Text(S.of(context).dialogCopyLabel),
                    ),
                  if (widget.userActivityList.isNotEmpty)
                    PopupMenuItem<_ActivityPopupMenuSelection>(
                      value: _ActivityPopupMenuSelection.onShare,
                      child: Text(S.of(context).shareActivityLabel),
                    ),
                  PopupMenuItem<_ActivityPopupMenuSelection>(
                    value: _ActivityPopupMenuSelection.onImport,
                    child: Text(S.of(context).importActivityLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: widget.userActivityList.length +
                1 +
                (widget.polarActiveKcal != null ? 1 : 0),
            itemBuilder: (BuildContext context, int index) {
              final hasPolar = widget.polarActiveKcal != null;
              if (hasPolar && index == 0) {
                return _buildPolarCard(context);
              }
              final adjustedIndex = hasPolar ? index - 1 : index;
              final firstListElement = adjustedIndex == 0 && !hasPolar;
              if (adjustedIndex == widget.userActivityList.length) {
                return PlaceholderCard(
                  day: widget.day,
                  onTap: () => _onPlaceholderCardTapped(context),
                  firstListElement: firstListElement,
                );
              } else {
                final userActivity = widget.userActivityList[adjustedIndex];
                return ActivityCard(
                  activityEntity: userActivity,
                  onItemLongPressed: widget.onItemLongPressedCallback,
                  onItemTapped: widget.onItemTappedCallback,
                  onItemDragCallback: widget.onItemDragCallback,
                  firstListElement: firstListElement,
                );
              }
            },
          ),
        ),
      ],
    );
  }

  void _onPlaceholderCardTapped(BuildContext context) {
    Navigator.of(context).pushNamed(
      NavigationOptions.addActivityRoute,
      arguments: AddActivityScreenArguments(day: widget.day),
    );
  }

  Widget _buildPolarCard(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 16),
        SizedBox(
          width: 120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 120,
                child: Card(
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12.0)),
                  ),
                  child: Stack(
                    children: [
                      Container(
                        margin: const EdgeInsets.all(8.0),
                        padding:
                            const EdgeInsets.fromLTRB(8.0, 4.0, 8.0, 4.0),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .tertiaryContainer
                              .withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '🔥${widget.polarActiveKcal!.toInt()} kcal',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onTertiaryContainer,
                                  ),
                        ),
                      ),
                      Center(
                        child: Icon(
                          Icons.monitor_heart_outlined,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 8.0),
                child: Text(
                  'Polar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 8.0),
                child: Text('heute', maxLines: 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
