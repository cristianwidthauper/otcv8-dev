deathWindow = nil

function init()
  g_ui.importStyle('deathwindow')

  connect(g_game, { onDeath = display,
                    onGameEnd = reset })
end

function terminate()
  disconnect(g_game, { onDeath = display,
                       onGameEnd = reset })

  reset()
end

function reset()
  if deathWindow then
    deathWindow:destroy()
    deathWindow = nil
  end
end

-- Samera 2026-06-21: death window simples. Mensagem unica + 1 botao Ok que reloga o char.
function display(deathType, penalty)
  reset()

  deathWindow = g_ui.createWidget('DeathWindow', rootWidget)
  deathWindow:setHeight(deathWindow.baseHeight + 95)
  deathWindow:setWidth(deathWindow.baseWidth)
  deathWindow:getChildById('labelText'):setText('VOCÊ SE FODEU!')

  local okFunc = function()
    reset()
    CharacterList.doLogin()
  end

  deathWindow.onEnter = okFunc
  deathWindow.onEscape = okFunc
  deathWindow:getChildById('buttonOk').onClick = okFunc
end
