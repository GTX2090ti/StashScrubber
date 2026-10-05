import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 中文文本选择工具栏（复制 / 全选 / 粘贴）。
/// 粘贴直接调用 Clipboard 读取并插入，避免鸿蒙上系统粘贴菜单偶发失效。
Widget zhContextMenuBuilder(BuildContext context, EditableTextState ets) {
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: ets.contextMenuAnchors,
    buttonItems: <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        label: '复制',
        onPressed: () {
          final sel = ets.textEditingValue.selection;
          if (sel.isValid && !sel.isCollapsed) {
            ets.copySelection(SelectionChangedCause.toolbar);
          }
          ets.hideToolbar();
        },
      ),
      ContextMenuButtonItem(
        label: '全选',
        onPressed: () => ets.selectAll(SelectionChangedCause.toolbar),
      ),
      ContextMenuButtonItem(
        label: '粘贴',
        onPressed: () async {
          ets.hideToolbar();
          final data = await Clipboard.getData(Clipboard.kTextPlain);
          final text = data?.text;
          if (text == null || text.isEmpty) return;
          final value = ets.textEditingValue;
          final sel = value.selection;
          final start = sel.isValid ? sel.start : value.text.length;
          final newText = value.text.substring(0, start) +
              text +
              value.text.substring(start);
          ets.userUpdateTextEditingValue(
            TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(
                offset: start + text.length,
              ),
            ),
            SelectionChangedCause.toolbar,
          );
        },
      ),
    ],
  );
}
