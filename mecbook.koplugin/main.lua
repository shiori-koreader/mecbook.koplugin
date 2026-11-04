local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local DocSettings = require("docsettings")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local JSON = require("json")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local Size = require("ui/size")
local NetworkMgr = require("ui/network/manager")
local ReadHistory = require("readhistory")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextViewer = require("ui/widget/textviewer")
local TitleBar = require("ui/widget/titlebar")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiutil = require("ffi/util")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local util = require("util")
local _ = require("gettext")
local T = ffiutil.template

local Client = require("api.client")
local Builder = require("epub.builder")
local Manager = require("loans.manager")
local BookDetail = require("books.detail")
local Metadata = require("storage.metadata")
local Paths = require("storage.paths")
local Rentals = require("loans.rentals")
local Serialize = require("storage.serialize")

local function reader_ui()
    return require("apps/reader/readerui")
end

local VERSION = "0.1.0-rc1"
local TOKEN_FILE = "mecbook_tokens.lua"

local DISCLAIMER = _([[O MECBook não é afiliado ao MEC.

Não é uma ferramenta de pirataria e não serve para redistribuir livros: ele só acessa os empréstimos ativos da sua própria conta, e o livro é apagado do Kindle quando o empréstimo termina.

Cada pessoa usa a própria conta, por sua conta e risco. O MEC pode bloquear o acesso a qualquer momento.]])

local function file_exists(path)
    return lfs.attributes(path, "mode") == "file"
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function write_file(path, data)
    util.makePath((path:match("^(.*)/[^/]*$")))
    local tmp = path .. ".tmp"
    local f = io.open(tmp, "wb")
    if not f then return false end
    local ok = f:write(data)
    f:close()
    if not ok then
        os.remove(tmp)
        return false
    end
    os.remove(path)
    return os.rename(tmp, path)
end

local function format_due(epoch)
    return os.date("%d/%m/%Y às %H:%M", epoch)
end

-- On devices that report a hardware keyboard with the virtual one disabled, InputText ignores taps,
-- so the field never shows a keyboard. Show it on tap anyway, and never before.
local function keyboard_on_tap(dialog)
    local input = dialog._input_widget
    local original = input.onTapTextBox
    if not original then return end
    input.onTapTextBox = function(widget, ...)
        local result = original(widget, ...)
        if not dialog:isKeyboardVisible() then
            dialog.skip_first_show_keyboard = nil
            widget:onShowKeyboard()
        end
        return result
    end
end

local function run_safely(fn)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
        logger.warn("MECBook: action failed:", tostring(err))
        UIManager:show(InfoMessage:new{ text = T(_("Algo deu errado: %1"), tostring(err):match("^[^\n]*")) })
    end
end

-- ButtonDialog sizes itself to its content; the title bar (with the close X) is added as a widget
-- because ButtonDialog has no title bar of its own. `content` is a string or a list of
-- {text, face, size, gap} blocks.
local function show_dialog(content, rows)
    local dialog
    local buttons = {}
    for _i, row in ipairs(rows) do
        buttons[#buttons + 1] = {{ text = row[1], callback = function()
            UIManager:close(dialog)
            if row[2] then run_safely(row[2]) end
        end }}
    end
    dialog = ButtonDialog:new{ buttons = buttons }
    local width = dialog:getAddedWidgetAvailableWidth()
    -- A single addWidget: ButtonDialog frees the previously added widgets on every call, which blanks their text.
    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = TitleBar:new{
        width = width,
        title = _("MECBook"),
        with_bottom_line = true,
        close_callback = function() UIManager:close(dialog) end,
        show_parent = dialog,
    }
    if type(content) == "string" then content = {{ text = content }} end
    for _i, block in ipairs(content or {}) do
        if block.text and block.text ~= "" then
            group[#group + 1] = VerticalSpan:new{ width = block.gap and Size.padding.large or Size.padding.small }
            group[#group + 1] = TextBoxWidget:new{
                text = block.text,
                width = width,
                face = Font:getFace(block.face or "cfont", block.size or 20),
            }
        end
    end
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.large }
    group.not_focusable = true
    dialog:addWidget(group)
    UIManager:show(dialog)
    return dialog
end

local function transport(req)
    local sink = {}
    local headers = {}
    for k, v in pairs(req.headers or {}) do headers[k] = v end
    local source
    if req.body then
        headers["Content-Length"] = tostring(#req.body)
        source = ltn12.source.string(req.body)
    end
    if req.url:find("/epub-proxy/", 1, true) then
        socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    else
        socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    end
    local code, resp_headers = socket.skip(1, http.request{
        url = req.url,
        method = req.method,
        headers = headers,
        source = source,
        sink = ltn12.sink.table(sink),
    })
    socketutil:reset_timeout()
    return {
        code = type(code) == "number" and code or nil,
        headers = resp_headers or {},
        body = table.concat(sink),
    }
end

local shared

local function build_shared()
    local s = {}
    s.paths = Paths.new(DataStorage:getDataDir())
    util.makePath(s.paths.archive_dir)
    s.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/mecbook_settings.lua")

    s.api = Client.new{
        transport = transport,
        json = JSON,
        sleep = ffiutil.sleep,
        version = VERSION,
        token = s.settings:readSetting("token"),
        refresh_token = s.settings:readSetting("refresh_token"),
        on_tokens = function(token, refresh)
            s.settings:saveSetting("token", token)
            s.settings:saveSetting("refresh_token", refresh)
            s.settings:flush()
        end,
    }

    local adapter = {
        find = function(path) return DocSettings:findSidecarFile(path, true) end,
        target = function(path)
            return DocSettings:getSidecarDir(path) .. "/" .. DocSettings.getSidecarFilename(path)
        end,
        read = function(file)
            local ok, data = pcall(dofile, file)
            return ok and type(data) == "table" and data or nil
        end,
        copy = function(src, dst)
            local data = read_file(src)
            return data ~= nil and write_file(dst, data)
        end,
        exists = file_exists,
        purge = function(path)
            DocSettings:open(path):purge()
            ReadHistory:removeItemByPath(path)
        end,
    }

    s.meta = Metadata.new(s.paths, adapter)
    s.manager = Manager.new({
        clock = os.time,
        store = {
            load = function()
                local data = read_file(s.paths.state_file)
                return data and Serialize.decode(data) or nil
            end,
            save = function(state) write_file(s.paths.state_file, Serialize.encode(state)) end,
        },
        fs = { exists = file_exists, remove = os.remove },
        meta = s.meta,
    }, { warn_days = s.settings:readSetting("warn_days", { 3 }), sync_interval = 3600 })
    s.tick = function()
        if s.plugin then
            s.plugin:localCheck()
            s.plugin:armTimer()
        end
    end
    return s
end

local function install_guard()
    local ReaderUI = reader_ui()
    if ReaderUI._mecbook_guard then return end
    ReaderUI._mecbook_guard = true
    local original = ReaderUI.showReader
    ReaderUI.showReader = function(self, file, ...)
        local allowed, removal = shared.manager:before_open(file)
        if not allowed then
            if shared.plugin then shared.plugin:showRemoved(removal) end
            return
        end
        return original(self, file, ...)
    end
end

local Mecbook = WidgetContainer:extend{
    name = "mecbook",
}

function Mecbook:init()
    if not shared then
        local ok, err = pcall(function()
            local built = build_shared()
            shared = built
            install_guard()
        end)
        if not ok then
            shared = nil
            Mecbook.init_error = tostring(err)
            logger.err("MECBook: init failed:", err)
        end
    end
    self.ui.menu:registerToMainMenu(self)
    if not shared then return end
    Dispatcher:registerAction("mecbook_open", {
        category = "none", event = "MecbookOpen", title = _("MECBook: abrir"), general = true,
    })
    Dispatcher:registerAction("mecbook_loan", {
        category = "none", event = "MecbookShowLoan", title = _("MECBook: meu empréstimo"), general = true,
    })
    Dispatcher:registerAction("mecbook_search", {
        category = "none", event = "MecbookSearch", title = _("MECBook: buscar livros"), general = true,
    })
    shared.plugin = self
    self:importTokenFile()
    UIManager:scheduleIn(2, function()
        self:localCheck()
        self:armTimer()
        self:maybeSync()
    end)
end

function Mecbook:importTokenFile()
    local path = DataStorage:getSettingsDir() .. "/" .. TOKEN_FILE
    if not file_exists(path) then return nil end
    local ok, cfg = pcall(dofile, path)
    if not ok or type(cfg) ~= "table" then
        logger.warn("MECBook: invalid token file")
        return _("O arquivo de chaves de acesso está com erro de sintaxe.")
    end
    local function clean(v) return type(v) == "string" and (v:gsub("%s+", "")) or "" end
    local token = clean(cfg.auth_token ~= nil and cfg.auth_token or cfg.token)
    local refresh = clean(cfg.refresh_token)
    if token == "" and refresh == "" then return nil end
    if token ~= "" then
        shared.settings:saveSetting("token", token)
        shared.api.token = token
    end
    if refresh ~= "" then
        shared.settings:saveSetting("refresh_token", refresh)
        shared.api.refresh_token = refresh
    end
    shared.settings:flush()
    write_file(path, 'return { auth_token = "", refresh_token = "" }\n')
    return _("Chaves de acesso importadas. O arquivo foi esvaziado por segurança.")
end

function Mecbook:showDisclaimerOnce()
    if shared.settings:isTrue("disclaimer_ok") then return end
    UIManager:nextTick(function()
        UIManager:show(ConfirmBox:new{
            text = DISCLAIMER,
            ok_text = _("Entendi"),
            cancel_text = _("Fechar"),
            ok_callback = function()
                shared.settings:saveSetting("disclaimer_ok", true)
                shared.settings:flush()
            end,
        })
    end)
end

function Mecbook:armTimer()
    UIManager:unschedule(shared.tick)
    local secs = shared.manager:seconds_until_due()
    if secs then UIManager:scheduleIn(math.min(secs + 1, 3600), shared.tick) end
end

function Mecbook:closeReaderOn(path)
    local reader = reader_ui().instance
    if reader and reader.document and reader.document.file == path then reader:onHome() end
end

function Mecbook:localCheck()
    local loan = shared.manager:loan()
    if loan and shared.manager:seconds_until_due() == 0 then self:closeReaderOn(loan.path) end
    self:handle(shared.manager:check())
end

function Mecbook:handle(result)
    if not result then return end
    if result.kind == "removed" then
        self:showRemoved(result)
    elseif result.kind == "expiring" then
        local loan = shared.manager:loan()
        local rows = {}
        if loan and loan.can_extend then
            rows[#rows + 1] = { _("Renovar (+14 dias)"), function() self:confirmRenew() end }
        end
        show_dialog(T(_("O empréstimo de “%1” termina em %2 dia(s), em %3.\n\nDepois disso o livro sai do Kindle, mas seu ponto de leitura fica guardado."),
            result.title, result.days, format_due(result.due)), rows)
    end
end

function Mecbook:showRemoved(removal)
    local lines = {}
    if removal.reason == "expired" then
        lines[1] = T(_("O prazo de “%1” terminou e o livro foi removido do Kindle."), removal.title)
    else
        lines[1] = T(_("“%1” foi devolvido e o livro foi removido do Kindle."), removal.title)
    end
    if removal.percent then
        lines[#lines + 1] = T(_("Você parou em %1%."), math.floor(removal.percent * 100))
        lines[#lines + 1] = _("Se pegar o livro de novo, a leitura continua daí.")
    end
    if removal.reason == "returned_here" then
        UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n\n") })
        return
    end
    show_dialog(table.concat(lines, "\n\n"), {
        { _("Pegar este livro de novo"), function() self:borrow(removal.book_id, removal.title) end },
        { _("Buscar outro livro"), function() self:searchBooks() end },
    })
end

function Mecbook:maybeSync(force)
    if not shared.manager:loan() then return end
    if not force and not shared.manager:needs_sync() then return end
    if not NetworkMgr:isConnected() then return end
    local ok, data, code = shared.api:active_rentals()
    if not ok then
        if data == "blocked" then self:showFailure(data, code) end
        return
    end
    local rentals = Rentals.list(data, os.time())
    local loan = shared.manager:loan()
    local still_active = false
    for _i, r in ipairs(rentals) do
        if tostring(r.id) == tostring(loan.rental_id) then still_active = true end
    end
    if not still_active then self:closeReaderOn(loan.path) end
    local removal = shared.manager:sync(rentals)
    if removal then self:showRemoved(removal) end
    self:armTimer()
end

function Mecbook:onResume()
    self:localCheck()
    self:armTimer()
    self:maybeSync()
end

function Mecbook:onMecbookOpen()
    self:showHome()
    return true
end

function Mecbook:onMecbookShowLoan()
    self:showLoan()
    return true
end

function Mecbook:onMecbookSearch()
    self:searchBooks()
    return true
end

function Mecbook:onReaderReady()
    self:localCheck()
end

function Mecbook:showFailure(err, code)
    local text
    if err == "blocked" then
        text = _("O MEC Livros não está aceitando acesso por este plugin. Use o site ou o app oficial. O MECBook só tenta de novo quando você reabrir o KOReader.")
    elseif err == "network_error" then
        text = _("Não consegui falar com o MEC Livros. Verifique o Wi-Fi e tente de novo.")
    elseif code == 401 then
        text = _("Sua sessão expirou. Importe novas chaves de acesso (MECBook > Chaves de acesso).")
    elseif type(err) == "table" and type(err.message) == "string" then
        text = err.message
    else
        text = T(_("Algo deu errado (%1). Tente de novo mais tarde."), tostring(code or err))
    end
    UIManager:show(InfoMessage:new{ text = text })
end

function Mecbook:ensureToken()
    if shared.api.token and shared.api.token ~= "" then return true end
    UIManager:show(InfoMessage:new{
        text = _("Primeiro configure o acesso: copie o arquivo mecbook_tokens.lua para a pasta settings do KOReader e abra MECBook > Chaves de acesso."),
    })
    return false
end

function Mecbook:addToMainMenu(menu_items)
    if not shared then
        menu_items.mecbook = {
            text = _("MECBook (erro)"),
            sorting_hint = "tools",
            callback = function()
                UIManager:show(InfoMessage:new{ text = Mecbook.init_error or _("Erro desconhecido.") })
            end,
        }
        return
    end
    menu_items.mecbook = {
        text = _("MECBook"),
        sorting_hint = "tools",
        sub_item_table_func = function()
            self:showDisclaimerOnce()
            return self:mainItems()
        end,
    }
end

function Mecbook:mainItems()
    return {
            { text = _("Meu empréstimo"), callback = function() self:showLoan() end },
            { text = _("Buscar livros"), callback = function() self:searchBooks() end },
            { text = _("Avisos de vencimento"), callback = function() self:showWarnDialog() end },
            { text = _("Chaves de acesso"), callback = function() self:importTokensAndShow() end },
            { text = _("Sobre"), callback = function() self:showAbout() end },
    }
end

function Mecbook:importTokensAndShow()
    local msg = self:importTokenFile()
    if not msg and shared.api.token and shared.api.token ~= "" then
        msg = _("Suas chaves de acesso já estão configuradas. Para trocar, cole as novas em settings/mecbook_tokens.lua e toque aqui de novo.")
    end
    UIManager:show(InfoMessage:new{
        text = msg or _("Nenhuma chave encontrada. Cole as chaves em settings/mecbook_tokens.lua e toque aqui de novo."),
    })
end

function Mecbook:showAbout()
    UIManager:show(InfoMessage:new{ text = DISCLAIMER })
end

function Mecbook:showHome()
    self:showDisclaimerOnce()
    show_dialog(nil, {
        { _("Meu empréstimo"), function() self:showLoan() end },
        { _("Buscar livros"), function() self:searchBooks() end },
        { _("Avisos de vencimento"), function() self:showWarnDialog() end },
        { _("Chaves de acesso"), function() self:importTokensAndShow() end },
        { _("Sobre"), function() self:showAbout() end },
    })
end

function Mecbook:showWarnDialog()
    local function current() return shared.settings:readSetting("warn_days", { 3 }) end
    local function has(d)
        for _i, v in ipairs(current()) do
            if v == d then return true end
        end
        return false
    end
    local function save(list)
        shared.settings:saveSetting("warn_days", list)
        shared.settings:flush()
        shared.manager:set_warn_days(list)
    end
    local function toggle(d)
        local out = {}
        for _i, v in ipairs(current()) do
            if v ~= d then out[#out + 1] = v end
        end
        if not has(d) then out[#out + 1] = d end
        save(out)
    end

    local presets = { [7] = true, [3] = true, [1] = true }
    local days = { 7, 3, 1 }
    for _i, d in ipairs(current()) do
        if not presets[d] then days[#days + 1] = d end
    end
    table.sort(days, function(a, b) return a > b end)

    local rows = {}
    for _i, d in ipairs(days) do
        local label = d == 1 and _("1 dia antes") or T(_("%1 dias antes"), d)
        rows[#rows + 1] = { (has(d) and "[x] " or "[  ] ") .. label, function()
            toggle(d)
            self:showWarnDialog()
        end }
    end
    rows[#rows + 1] = { _("Outro número de dias…"), function()
        local dialog
        dialog = InputDialog:new{
            title = _("Avisar quantos dias antes?"),
            input_type = "number",
            buttons = {{
                { text = _("Cancelar"), callback = function()
                    UIManager:close(dialog)
                    self:showWarnDialog()
                end },
                { text = _("Adicionar"), is_enter_default = true, callback = function()
                    local n = tonumber(dialog:getInputText())
                    UIManager:close(dialog)
                    if n and n >= 1 and n <= 60 and n == math.floor(n) then
                        if not has(n) then toggle(n) end
                    else
                        UIManager:show(InfoMessage:new{ text = _("Digite um número inteiro de 1 a 60.") })
                    end
                    self:showWarnDialog()
                end },
            }},
        }
        UIManager:show(dialog)
        keyboard_on_tap(dialog)
    end }
    rows[#rows + 1] = { (#current() == 0 and "[x] " or "[  ] ") .. _("Não avisar"), function()
        save({})
        self:showWarnDialog()
    end }
    show_dialog(_("Avisar antes do fim do empréstimo"), rows)
end

function Mecbook:withProgress(action)
    NetworkMgr:runWhenOnline(function() Trapper:wrap(action) end)
end

function Mecbook:showLoan()
    local loan = shared.manager:loan()
    if not loan then
        if not self:ensureToken() then return end
        self:withProgress(function() self:offerServerLoan() end)
        return
    end
    local days = math.ceil(math.max(loan.due - os.time(), 0) / 86400)
    local title = T(_("%1\nVence em %2 (%3 dia(s))"), loan.title, format_due(loan.due), days)
    local rows = { { _("Ler"), function() reader_ui():showReader(loan.path) end } }
    if loan.can_extend then
        rows[#rows + 1] = { _("Renovar (+14 dias)"), function() self:confirmRenew() end }
    else
        title = title .. "\n" .. _("Este empréstimo não pode ser renovado agora.")
    end
    if self:readFraction(loan) >= 0.9 then
        rows[#rows + 1] = { _("Devolver"), function() self:confirmReturn() end }
    else
        title = title .. "\n" .. _("A plataforma só libera a devolução depois de 90% lido.")
    end
    show_dialog(title, rows)
end

function Mecbook:readFraction(loan)
    local reader = reader_ui().instance
    if reader and reader.document and reader.document.file == loan.path then reader:saveSettings() end
    return shared.meta.progress(loan.path) or 0
end

function Mecbook:confirmReturn()
    UIManager:show(ConfirmBox:new{
        text = _("Devolver este livro agora?\n\nEle sai do Kindle, mas seu ponto de leitura fica guardado."),
        ok_text = _("Devolver"),
        ok_callback = function() self:returnLoan() end,
    })
end

function Mecbook:returnLoan()
    self:withProgress(function()
        Trapper:info(_("Devolvendo o livro…"))
        local removal, err = shared.manager:return_loan(function(loan)
            local fraction = self:readFraction(loan)
            local ok, data, code = shared.api:report_progress(loan.book_id, fraction, os.date("!%Y-%m-%dT%H:%M:%S.000Z"))
            if ok then ok, data, code = shared.api:return_rental(loan.rental_id) end
            if ok then self:closeReaderOn(loan.path) end
            return ok, { data, code }
        end)
        Trapper:clear()
        if not removal then
            local detail = type(err) == "table" and err or {}
            logger.warn("MECBook: return failed, HTTP", tostring(detail[2]))
            return self:showFailure(detail[1], detail[2])
        end
        self:armTimer()
        self:showRemoved(removal)
    end)
end

function Mecbook:offerServerLoan()
    Trapper:info(_("Procurando seu empréstimo…"))
    local ok, data, code = shared.api:active_rentals()
    if not ok then
        Trapper:clear()
        return self:showFailure(data, code)
    end
    local rental = Rentals.list(data, os.time())[1]
    if not rental then
        Trapper:clear()
        UIManager:show(InfoMessage:new{ text = _("Você não tem nenhum livro emprestado no momento.") })
        return
    end
    local go = Trapper:confirm(T(_("Você tem “%1” emprestado. Baixar para ler?"), rental.title or _("um livro")),
        _("Agora não"), _("Baixar"))
    if go then self:download(rental) else Trapper:clear() end
end

function Mecbook:confirmRenew()
    UIManager:show(ConfirmBox:new{
        text = _("Renovar por mais 14 dias?\n\nA renovação conta como 1 dos seus 4 empréstimos a cada 30 dias e 1 dos 4 resgates deste título."),
        ok_text = _("Renovar"),
        ok_callback = function() self:renewLoan() end,
    })
end

function Mecbook:renewLoan()
    local loan = shared.manager:loan()
    NetworkMgr:runWhenOnline(function()
        local ok, data, code = shared.api:extend(loan.rental_id)
        if not ok then return self:showFailure(data, code) end
        self:maybeSync(true)
        UIManager:show(InfoMessage:new{ text = _("Empréstimo renovado.") })
    end)
end

function Mecbook:searchBooks()
    if not self:ensureToken() then return end
    local dialog
    dialog = InputDialog:new{
        title = _("Buscar livros"),
        buttons = {{
            { text = _("Cancelar"), callback = function() UIManager:close(dialog) end },
            { text = _("Buscar"), is_enter_default = true, callback = function()
                local query = dialog:getInputText()
                UIManager:close(dialog)
                if query ~= "" then NetworkMgr:runWhenOnline(function() self:doSearch(query) end) end
            end },
        }},
    }
    UIManager:show(dialog)
    keyboard_on_tap(dialog)
end

function Mecbook:doSearch(query)
    local ok, data, code = shared.api:search(query, 1, 30)
    if not ok then return self:showFailure(data, code) end
    local books = type(data) == "table" and (data.books or data.results) or {}
    if #books == 0 then
        UIManager:show(InfoMessage:new{ text = _("Nenhum livro encontrado.") })
        return
    end
    local items = {}
    for _i, book in ipairs(books) do
        local authors = type(book.authors) == "table" and table.concat(book.authors, ", ") or book.authors
        local title = book.title or book.book_title or _("(sem título)")
        items[#items + 1] = {
            text = (authors and authors ~= "") and (title .. " — " .. authors) or title,
            book_id = book.id or book.book_id,
            title = title,
        }
    end
    local menu
    menu = Menu:new{
        title = T(_("Resultados: %1"), query),
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        onMenuSelect = function(_menu, item)
            self:showBook(item)
        end,
        close_callback = function()
            self.results_menu = nil
            UIManager:close(menu)
        end,
    }
    self.results_menu = menu
    UIManager:show(menu)
end

function Mecbook:showBook(item)
    NetworkMgr:runWhenOnline(function()
        local ok, data, code = shared.api:book(item.book_id)
        if not ok then return self:showFailure(data, code) end
        self:showBookDetail(item, data)
    end)
end

function Mecbook:showBookDetail(item, data)
    local detail = BookDetail.summary(data)
    local rows = {}
    if detail.borrowable then
        local label = detail.public_domain and _("Ler") or _("Pegar emprestado")
        rows[#rows + 1] = { label, function() self:borrow(item.book_id, item.title) end }
    end
    if detail.truncated then
        rows[#rows + 1] = { _("Ler sinopse completa"), function() self:showSynopsis(item, data, detail) end }
    end
    local note
    if detail.borrowable and not detail.public_domain then
        note = _("Conta como 1 dos seus 4 empréstimos a cada 30 dias e 1 dos 4 resgates deste título. Renovações também contam.")
    end
    show_dialog({
        { text = detail.title, face = "tfont", size = 26 },
        { text = detail.authors, size = 20 },
        { text = detail.facts, size = 17 },
        { text = detail.categories, size = 17 },
        { text = detail.status, face = "tfont", size = 18, gap = true },
        { text = detail.description, size = 18, gap = true },
        { text = note, size = 16, gap = true },
    }, rows)
end

function Mecbook:showSynopsis(item, data, detail)
    UIManager:show(TextViewer:new{
        title = detail.title,
        text = detail.full_description,
        show_menu = false,
        buttons_table = {},
        close_callback = function() self:showBookDetail(item, data) end,
    })
end

local CHECKOUT_ERRORS = {
    ACTIVE_RENTAL_EXISTS = _("Você já tem outro livro emprestado na sua conta. A plataforma só libera outro quando o atual terminar."),
    NO_COPIES_AVAILABLE = _("Não há cópias disponíveis agora."),
    RENTAL_CYCLE_EXHAUSTED = _("Você já usou os 4 resgates deste título (empréstimos e renovações somam). Não dá para pegá-lo de novo."),
}

function Mecbook:borrow(book_id, title)
    if not self:ensureToken() then return end
    local current = shared.manager:loan()
    if current and not shared.manager.fs.exists(current.path) then current = nil end
    if not current then return self:doBorrow(book_id) end
    if tostring(current.book_id) == tostring(book_id) then
        show_dialog(T(_("Você já está com “%1” emprestado e baixado."), current.title), {
            { _("Ler agora"), function() reader_ui():showReader(current.path) end },
        })
        return
    end
    show_dialog(T(_("Você já está com “%1” emprestado, e só dá para ter um livro por vez.\n\nA plataforma só libera outro empréstimo quando este terminar, em %2."),
        current.title, format_due(current.due)), {
        { T(_("Ler “%1” agora"), current.title), function() reader_ui():showReader(current.path) end },
    })
end

-- A loan for another book than the one asked for: nothing is borrowed, the reader is pointed at the loan.
function Mecbook:showOtherLoan(rental)
    local text = T(_("Você já está com “%1” emprestado, e só dá para ter um livro por vez."), rental.title or _("outro livro"))
    if rental.due then
        text = text .. "\n\n" .. T(_("A plataforma só libera outro empréstimo quando este terminar, em %1."), format_due(rental.due))
    end
    show_dialog(text, {
        { T(_("Baixar “%1” neste Kindle"), rental.title or _("o livro")), function()
            self:withProgress(function() self:download(rental) end)
        end },
    })
end

-- Must run inside Trapper:wrap. Returns the account's active rental or nil; shows the failure itself.
function Mecbook:activeRental()
    local ok, data, code = shared.api:active_rentals()
    if not ok then
        Trapper:clear()
        self:showFailure(data, code)
        return nil, true
    end
    return Rentals.list(data, os.time())[1]
end

function Mecbook:doBorrow(book_id)
    self:withProgress(function()
        logger.info("MECBook: borrow start")
        Trapper:info(_("Verificando seus empréstimos…"))
        local active, failed = self:activeRental()
        if failed then return end
        if active then
            if tostring(active.book_id) == tostring(book_id) then return self:download(active) end
            Trapper:clear()
            return self:showOtherLoan(active)
        end

        Trapper:info(_("Pegando o livro emprestado…"))
        local ok, data, code = shared.api:checkout(book_id)
        logger.info("MECBook: checkout result:", tostring(ok), tostring(code))
        if not ok then
            Trapper:clear()
            local err = type(data) == "table" and (data.code or data.error or data.errorCode) or nil
            if CHECKOUT_ERRORS[err] then
                UIManager:show(InfoMessage:new{ text = CHECKOUT_ERRORS[err] })
            else
                self:showFailure(data, code)
            end
            return
        end

        local rental, listing_failed = self:activeRental()
        if listing_failed then return end
        if rental and tostring(rental.book_id) == tostring(book_id) then return self:download(rental) end
        Trapper:clear()
        UIManager:show(InfoMessage:new{ text = _("O empréstimo foi feito, mas não encontrei o livro na sua conta. Tente MECBook > Meu empréstimo.") })
    end)
end

-- Must run inside Trapper:wrap.
function Mecbook:download(rental)
    if not rental.due then
        Trapper:clear()
        UIManager:show(InfoMessage:new{ text = _("Não consegui saber até quando vai o empréstimo, então não baixei o livro.") })
        return
    end
    Trapper:info(_("Preparando o livro…"))
    local ok, manifest, code = shared.api:manifest(rental.book_id)
    if not ok then
        Trapper:clear()
        return self:showFailure(manifest, code)
    end

    local epub, result = Builder.build(rental.book_id, manifest, shared.api.origin,
        function(url)
            local rok, content = shared.api:get_raw(url)
            return rok, content
        end,
        function(i, total, title)
            if i == 1 or i % 5 == 0 or i == total then
                return Trapper:info(T(_("Baixando “%1”…\n\n%2%"), title, math.floor(i * 100 / total)))
            end
            return true
        end)
    if not epub then
        Trapper:clear()
        if result == "cancelled" then return end
        if shared.api.blocked then return self:showFailure("blocked", 403) end
        UIManager:show(InfoMessage:new{ text = _("Não consegui baixar o livro inteiro. Tente de novo.") })
        return
    end

    local path = shared.paths.book(rental.book_id)
    util.makePath(shared.paths.cache_dir)
    if not write_file(path, epub) then
        Trapper:clear()
        UIManager:show(InfoMessage:new{ text = _("Não consegui salvar o livro no Kindle (falta espaço?).") })
        return
    end

    shared.manager:start({
        rental_id = rental.id,
        book_id = rental.book_id,
        title = rental.title or result,
        due = rental.due,
        can_extend = rental.can_extend,
        path = path,
    })
    shared.meta.restore(rental.book_id, path)
    self:armTimer()
    Trapper:clear()
    if self.results_menu then
        UIManager:close(self.results_menu)
        self.results_menu = nil
    end
    UIManager:nextTick(function() reader_ui():showReader(path) end)
end

return Mecbook
