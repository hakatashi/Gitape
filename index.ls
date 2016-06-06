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

  # Layout X-axis
  commit-levels.0.for-each (commit) -> commit.type = \real
  level-layouts = [commit-levels.0]

  for level, y in commit-levels when y >= 1
    previous-layout = level-layouts[* - 1]
    new-layout = []

    # Layout virtual commits first
    for previous-commit, x in previous-layout when previous-commit isnt undefined
      if previous-commit.type is \virtual
        new-layout[x] = Object.assign {} previous-commit

    # Next, layout real commits
    for previous-commit, x in previous-layout when previous-commit isnt undefined
      if previous-commit.type is \real
        for parent in previous-commit.parents
          #assert.equal previous-commit.level-index, y - 1, util.inspect {x, y, level, previous-layout, new-layout, previous-commit, parent}, depth: 4
          distance = parent.level-index - (y - 1)

          parent-commit =
            if distance is 1
              real-parent = Object.assign {} parent
              real-parent.type = \real
              real-parent
            else
              # Clone parent commit and mark it as virtual
              virtual-parent = Object.assign {} parent
              virtual-parent.type = \virtual
              virtual-parent

          # Skip if parent commit is already laid out virtually or really
          existing-commit = new-layout.filter (isnt undefined) .find (.hash is parent.hash)
          if existing-commit
            if existing-commit.type is \virtual and parent-commit.type is \real
              existing-commit.type = \real
            continue

          spare-index = new-layout.find-index (is undefined)
          if spare-index isnt -1
            new-layout[spare-index] = parent-commit
          else
            new-layout.push parent-commit

    level-layouts.push new-layout

  svg = do
    svg:
      $:
        xmlns: 'http://www.w3.org/2000/svg'
        width: 1800
        height: commit-levels.length * 50 + 60

  for layout, layout-index in level-layouts
    next-layout = level-layouts[layout-index + 1]

    for commit, commit-index in layout when commit isnt undefined
      if commit.type is \real
        cx = commit-index * 30 + 15
        cy = layout-index * 50 + 30
        svg.svg.[]circle.push $: {cx, cy, r: 10}

        for parent in commit.parents
          parent-index = next-layout.filter (isnt undefined) .find-index (.hash is parent.hash)
          parent-x = parent-index * 30 + 15
          parent-y = (layout-index + 1) * 50 + 30

          svg.svg.[]line.push $: {
            x1: cx
            y1: cy
            x2: parent-x
            y2: parent-y
            'stroke-width': 3
            stroke: \black
          }

      if commit.type is \virtual
        x1 = commit-index * 30 + 15
        y1 = layout-index * 50 + 30
        y2 = (layout-index + 1) * 50 + 30
        svg.svg.[]line.push $: {
          x1: x1
          y1: y1
          x2: x1
          y2: y2
          'stroke-width': 3
          stroke: \red
        }

  builder = new xml2js.Builder {+explicit-root}

  process.stdout.write builder.build-object svg
