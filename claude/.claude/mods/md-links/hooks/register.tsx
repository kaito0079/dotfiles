import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { Recent } from '../types'

// Write で作った .md を新しい順に最大 MAX 件並べる
const MAX = 5
const recent = atom({ plugin: 'md-links', key: 'recent' } as const, [] as Recent)

const basename = (path: string) => path.slice(path.lastIndexOf('/') + 1)

export const register: Register = on => {
  on('tool.call', { tool: 'Write' }, async ($, e, next) => {
    const ran = await next(e)
    const path = e.file_path

    if (ran.deny === undefined && ran.isError !== true && path.endsWith('.md')) {
      await update($, recent, list => [path, ...list.filter(p => p !== path)].slice(0, MAX))
    }

    return ran
  }).catch(($, e, next) => next(e)) // 記録に失敗しても Write 自体は止めない

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const list = await read($, recent)

    if (e.props.hasSurvey || list.length === 0) {
      return next(e)
    }

    const { Box, Button, Text } = $.ui.resolve(e)

    // 右ペインに積む処理は既存のヘルパーに任せる (~ を展開するため bash 経由)
    const open = async (path: string) => {
      const res = await $.process.run([
        'bash',
        '-c',
        'python3 ~/.claude/hooks/cmux_preview.py markdown "$1"',
        '_',
        path,
      ])
      if (res.exitCode !== 0) {
        $.ui.toast(`md-links: failed to open ${basename(path)}`)
      }
    }

    return (
      <Box>
        <Text dimColor>md: </Text>
        {list.map((path, i) => (
          <Button
            key={path}
            label={basename(path)}
            hotkey={String(i + 1)}
            onPress={() => open(path)}
          />
        ))}
        <Button key="clear" label="×" onPress={() => update($, recent, () => [])} />
      </Box>
    )
  })
}
