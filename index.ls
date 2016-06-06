require! {
  util
  xml2js
  assert
  minimist
  'concat-stream'
  child_process: {spawn}
}

{_: [commitish]} = minimist process.argv[2 to]

git-log = spawn \git ['log' '--pretty=format:%H %P' commitish]

git-log.stdout.pipe concat-stream (log-buffer) ->
  log = log-buffer.to-string!

  commits = log.split '\n' .map (line, index) ->
    [hash, ...parents] = line.split ' '
    parents .= filter (isnt '')
    {hash, parents, children: []}

  commit-hashes = Object.create null

  # Create reverse hash of commits by hash key
  for commit in commits
    commit-hashes[commit.hash] = commit

  # Caluculate children field for commits
  for commit in commits
    commit.parents .= map (parent-hash) -> commit-hashes[parent-hash]

    for parent in commit.parents
      parent.children.push commit

  # Abbreviate logs
  for commit, index in commits
    if commit.parents.length isnt 1
    or commit.children.length isnt 1
    or commit.parents.0.children.length isnt 1
    or commit.children.0.parents.length isnt 1
      continue

    parent = commit.parents.0
    child = commit.children.0

    parent.children = [child]
    child.parents = [parent]

    commits[index] = null

  commits .= filter (isnt null)

  for commit, index in commits
    commit.index = index

  # Compress commits by pushing them into commit levels
  commit-levels = []

  for commit in commits
    shallowest-index-parents-exists = -1

    # FIXME: O(N^2)
    for child in commit.children
      level-index = commit-levels.find-index (level) -> level.some (is child)
      assert level-index isnt -1

      level = commit-levels[level-index]
      assert level isnt undefined

      if shallowest-index-parents-exists < level-index
        shallowest-index-parents-exists = level-index

    commit-levels.[][shallowest-index-parents-exists + 1].push commit
    commit.level-index = shallowest-index-parents-exists + 1
    commit.level = commit-levels[shallowest-index-parents-exists + 1]

  svg = do
    svg:
      $:
        xmlns: 'http://www.w3.org/2000/svg'
        width: 1800
        height: commit-levels.length * 50 + 60

  for level, level-index in commit-levels
    for commit, commit-index in level
      cx = commit-index * 200 + 30
      cy = level-index * 50 + 30
      svg.svg.[]circle.push $: {cx, cy, r: 15}

      svg.svg.[]text.push _: commit.hash.slice(0, 10), $: {
        x: cx + 20
        y: cy + 5
        'font-size': 20
      }

      for parent in commit.parents
        parent-x = parent.level.index-of(parent) * 200 + 30
        parent-y = parent.level-index * 50 + 30

        svg.svg.[]line.push $: {
          x1: cx
          y1: cy
          x2: parent-x
          y2: parent-y
          'stroke-width': 3
          stroke: \black
        }

  builder = new xml2js.Builder {+explicit-root}

  process.stdout.write builder.build-object svg
