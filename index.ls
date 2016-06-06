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
    if parents.0 is ''
      parents = []
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

  # Compress commits by pushing them into commit groups
  commit-groups = []

  for commit in commits
    shallowest-index-parents-exists = -1

    # FIXME: O(N^2)
    for child in commit.children
      group = commit-groups.find (group) -> group.some (is child)
      assert group isnt undefined, util.inspect commit

      group-index = commit-groups.index-of group
      assert group-index isnt -1

      if shallowest-index-parents-exists < group-index
        shallowest-index-parents-exists = group-index

    commit-groups.[][shallowest-index-parents-exists + 1].push commit
    commit.group-index = shallowest-index-parents-exists + 1
    commit.group = commit-groups[shallowest-index-parents-exists + 1]

  svg = do
    svg:
      $:
        xmlns: 'http://www.w3.org/2000/svg'
        width: 2000
        height: commits.length * 50 + 60
      circle: []
      line: []
      text: []

  for group, group-index in commit-groups
    for commit, commit-index in group
      cx = (commit-index + group-index % 3) * 200 + 30
      cy = group-index * 50 + 30
      svg.svg.circle.push $: {cx, cy, r: 15}

      svg.svg.text.push _: commit.hash.slice(0, 10), $: {
        x: cx + 20
        y: cy + 5
        'font-size': 20
      }

      for parent in commit.parents
        parent-x = (parent.group.index-of(parent) + parent.group-index % 3) * 200 + 30
        parent-y = parent.group-index * 50 + 30

        svg.svg.line.push $: {
          x1: cx
          y1: cy
          x2: parent-x
          y2: parent-y
          'stroke-width': 3
          stroke: \black
        }

  builder = new xml2js.Builder {+explicit-root}

  process.stdout.write builder.build-object svg
