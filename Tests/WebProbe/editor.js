import {EditorView, keymap} from '@codemirror/view';
import {markdown, markdownKeymap} from '@codemirror/lang-markdown';
import {vim, Vim, getCM} from '@replit/codemirror-vim';
import {history, historyKeymap, undo, redo, isolateHistory} from '@codemirror/commands';

// Core editor versions match SilverBullet's 2.10.0 lockfile. This is a small comparison
// fixture, not a claim that the complete SilverBullet configuration is loaded.
let view, records = [];
const report = document.getElementById('report');
const send = row => {
  row.time = performance.now();
  records.push(row); report.value = JSON.stringify(records, null, 1);
  window.webkit.messageHandlers.trace.postMessage(row);
};
function state(current = view) {
  return {text: current.state.doc.toString(), composing: current.composing,
    selection: current.state.selection.main.head};
}
window.resetEditor = (useVim = false) => {
  if (view) view.destroy();
  records = []; report.value = '';
  view = new EditorView({
    doc: '- ', parent: document.getElementById('editor'),
    selection: {anchor: 2},
    extensions: [
      ...(useVim ? [vim()] : []), markdown(), history(), keymap.of([...markdownKeymap, ...historyKeymap]),
      EditorView.updateListener.of(update => {
        if (update.docChanged) send({type: 'editor.update', ...state()});
      })
    ]
  });
  for (const type of ['keydown', 'keyup', 'beforeinput', 'input', 'compositionstart', 'compositionupdate', 'compositionend']) {
    const current = view;
    view.contentDOM.addEventListener(type, e => {
      send({type, key: e.key || '', keyCode: e.keyCode || 0,
        isComposing: !!e.isComposing, inputType: e.inputType || '', data: e.data || '', ...state()});
      if (type === 'keydown' && e.key === 'Enter') queueMicrotask(() => send({type: 'Enter.afterDispatch', prevented: e.defaultPrevented, ...state(current)}));
    }, true);
  }
  if (useVim) Vim.handleKey(getCM(view), 'i');
  view.focus();
};
window.focusEditor = () => view.focus();
window.probeSnapshot = () => ({...state(), events: records});
// A separate editor-level regression check. It does not claim to traverse IMK.
window.editorRegression = () => {
  const results = [];
  const check = (name, useVim, expected, extra = {}) => results.push({
    name, useVim, text: view.state.doc.toString(), expected,
    passed: view.state.doc.toString() === expected && !view.composing
      && extra.handled !== false && extra.prevented !== false, ...extra
  });
  const replace = (from, to, insert) => view.dispatch({
    changes: {from, to, insert}, selection: {anchor: from + insert.length},
    annotations: isolateHistory.of('full')
  });
  for (const useVim of [false, true]) {
    window.resetEditor(useVim);
    replace(2, 2, '어렵다');
    const event = new KeyboardEvent('keydown', {key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true, cancelable: true});
    view.contentDOM.dispatchEvent(event);
    check('Enter continues list', useVim, '- 어렵다\n- ', {prevented: event.defaultPrevented});
    const beforePaste = view.state.doc.toString();
    // The editor's actual paste listener, using fixed local clipboard data.
    // This does not touch the system clipboard or simulate IMK key delivery.
    const data = new DataTransfer();
    data.setData('text/plain', '붙여넣기 😀');
    const paste = new ClipboardEvent('paste', {clipboardData: data, bubbles: true, cancelable: true});
    view.contentDOM.dispatchEvent(paste);
    check('paste after Enter', useVim, beforePaste + '붙여넣기 😀', {prevented: paste.defaultPrevented});
    check('undo paste', useVim, beforePaste, {handled: undo(view)});
    check('redo paste', useVim, beforePaste + '붙여넣기 😀', {handled: redo(view)});
    const end = view.state.doc.length;
    replace(end, end, 'ㄱ');
    replace(end, end + 1, '가');
    check('replace syllable after redo', useVim, beforePaste + '붙여넣기 😀가');
    replace(0, view.state.doc.length, '새 문서');
    check('undo document replacement', useVim, beforePaste + '붙여넣기 😀가', {handled: undo(view)});
    check('redo document replacement', useVim, '새 문서', {handled: redo(view)});
    // Model a cleared chat editor while keeping the same EditorView.
    replace(0, view.state.doc.length, '');
    replace(0, 0, 'ㄴ');
    replace(0, 1, '나');
    check('compose in cleared document', useVim, '나');
  }
  send({type: 'editor.regression', results});
  return results;
};
window.resetEditor();
