unit kn_LinksMng;

interface
uses
  Controls, kn_LocationObj;

   // Links related routines         (initially in kn_main.pas)
    procedure InsertFileOrLink( const aFileName : string; const AsLink : boolean );
    procedure InsertOrMarkKNTLink( aLocation : TLocation; const AsInsert : boolean );
    function BuildKNTLocationText( const aLocation : TLocation ) : string;
    procedure JumpToKNTLocation( LocationStr : string );
    procedure ClickOnURL(const URLText: String);
    procedure InsertURL();

    {
    procedure InsertHyperlink(
      const aLinkType : TLinkType;
      aLinkText, aLinkTarget : string;
      const aLocation : TLocation );
    procedure CreateHyperlink;
    }

implementation
uses
    Windows, Forms, SysUtils, Dialogs, StdCtrls, Clipbrd, ShellApi,
    gf_misc, gf_miscvcl, RichEdit, RxRichEd, TreeNT,
    kn_Global, kn_Main, kn_Info, kn_Const, kn_URL, kn_RTFUtils, kn_NoteObj;

//===============================================================
// InsertFileOrLink
//===============================================================
procedure InsertFileOrLink( const aFileName : string; const AsLink : boolean );
var
  fn : string;
  oldFilter : string;
  ImportFileType : TImportFileType;
  ext : string;
  RTFAux: TRxRichEdit;

  // RTFStream : TMemoryStream;
begin
  if ( not ( Form_Main.HaveNotes( true, true ) and assigned( ActiveNote ))) then exit;
  if Form_Main.NoteIsReadOnly( ActiveNote, true ) then exit;

  if ( aFileName = '' ) then
  begin
    with Form_Main.OpenDlg do
    begin
      oldFilter := Filter;
      if AsLink then
        Filter := FILTER_FILELINK
      else
        Filter := FILTER_RTFFILES + '|' +
                  FILTER_TEXTFILES + '|' +
                  FILTER_ALLFILES;
      FilterIndex := 1;
      if AsLink then
        Title := 'Select file to link to'
      else
        Title := 'Select file to insert';
      Options := Options - [ofAllowMultiSelect];
      Form_Main.OpenDlg.FileName := '';
      if ( KeyOptions.LastImportPath <> '' ) then
        InitialDir := KeyOptions.LastImportPath
      else
        InitialDir := GetFolderPath( fpPersonal );
    end;

    try
      if ( not Form_Main.OpenDlg.Execute ) then exit;
      FN := Form_Main.OpenDlg.FileName;
      KeyOptions.LastImportPath := properfoldername( extractfilepath( FN ));
    finally
      Form_Main.OpenDlg.Filter := oldFilter;
      Form_Main.OpenDlg.FilterIndex := 1;
    end;
  end
  else
  begin
    FN := aFileName;
  end;

    if AsLink then
    begin
      FN := 'file:///' + FileNameToURL( FN );
      ActiveNote.Editor.SelText := FN + #32;
      ActiveNote.Editor.SelLength := 0;
    end
    else
    begin
      ext := extractfileext( FN );
      ImportFileType := itText;
      if ( ext = ext_RTF ) then
        ImportFileType := itRTF
      else
      if Form_Main.ExtIsHTML( ext ) then
        ImportFileType := itHTML
      else
      if Form_Main.ExtIsText( ext ) then
        ImportFileType := itText
      else
      begin
        messagedlg( 'The file you selected is not a plain-text or RTF file and cannot be inserted.',
          mtError, [mbOK], 0 );
        exit;
      end;

      ActiveNote.Editor.Lines.BeginUpdate;

      RTFAux := TRxRichEdit.Create( ActiveNote.TabSheet);
      RTFAux.Visible:= False;
      RTFAux.Parent:=ActiveNote.TabSheet ;

      try
        try

        case ImportFileType of
          itText, itHTML : begin
            RTFAux.PlainText := true;
            RTFAux.Lines.LoadFromFile( FN );
            ActiveNote.Editor.SelText := RTFAux.Lines.Text;
            ActiveNote.Editor.SelLength := 0;
          end;

          itRTF : begin
            RTFAux.Lines.LoadFromFile( FN );

            PutRichText(
              GetRichText( RTFAux, true, false ),
              ActiveNote.Editor,
              true, true );

          end;
        end;

        except
          on E : Exception do
          begin
            messagedlg( E.Message, mtError, [mbOK], 0 );
            exit;
          end;
        end;

      finally
        ActiveNote.Editor.Lines.EndUpdate;
        RTFAux.Free;
      end;

    end;

    NoteFile.Modified := true;
    Form_Main.UpdateNoteFileState( [fscModified] );

end; // InsertFileOrLink

//===============================================================
// InsertOrMarkKNTLink
//===============================================================
procedure InsertOrMarkKNTLink( aLocation : TLocation; const AsInsert : boolean );
begin
  if ( not Form_Main.HaveNotes( true, true )) then exit;
  if ( not assigned( ActiveNote )) then exit;
  if ( aLocation = nil ) then
    aLocation := _KNTLocation;

  if AsInsert then
  begin
    // insert link to previously marked location
    if Form_Main.NoteIsReadOnly( ActiveNote, true ) then exit;
    if ( aLocation.FileName = '' ) then
    begin
      showmessage( 'Cannot insert link to a KeyNote location, because no location has been marked. First, mark a location to which you want to link.' );
      exit;
    end;

    ActiveNote.Editor.SelText := BuildKNTLocationText( aLocation );
    ActiveNote.Editor.SelLength := 0;
    Form_Main.StatusBar.Panels[PANEL_HINT].Text := ' Location inserted';

  end
  else
  begin
    // mark caret position as TLocation
    with aLocation do
    begin
      // [x] we should use IDs instead, but the
      // links would then be meaningless to user!
      FileName := normalFN( NoteFile.FileName );
      NoteName := ActiveNote.Name;
      NoteID := ActiveNote.ID;
      if ( ActiveNote.Kind = ntTree ) then
      begin
        NodeName := TTreeNote( ActiveNote ).SelectedNode.Name;
        NodeID := TTreeNote( ActiveNote ).SelectedNode.ID;
      end
      else
      begin
        NodeName := '';
        NodeID := 0;
      end;
      CaretPos := ActiveNote.Editor.SelStart;
      SelLength := ActiveNote.Editor.SelLength;
    end;

    Form_Main.StatusBar.Panels[PANEL_HINT].Text := ' Current location marked';

  end;

end; // InsertOrMarkKNTLink


//===============================================================
// BuildKNTLocationText
//===============================================================
function BuildKNTLocationText( const aLocation : TLocation ) : string;
var
  LocationString : string;
begin
  if ( aLocation.FileName = normalFN( NoteFile.FileName )) then
    LocationString := ''
  else
    LocationString := FileNameToURL( aLocation.FileName );

  // [x] this does not handle files on another computer, i.e.
  // we cannot do file://computername/pathname/file.knt
  LocationString := 'file:///' + LocationString + KNTLOCATION_MARK_OLD +
    FileNameToURL( aLocation.NoteName ) + KNTLINK_SEPARATOR +
    FileNameToURL( aLocation.NodeName ) + KNTLINK_SEPARATOR +
    inttostr( aLocation.CaretPos ) + KNTLINK_SEPARATOR +
    inttostr( aLocation.SelLength );

  result := LocationString;
end; // BuildKNTLocationText


//===============================================================
// JumpToKNTLocation
//===============================================================
procedure JumpToKNTLocation( LocationStr : string );
type
  EInvalidLocation = Exception;
var
  p, pold, pnew : integer;
  Location : TLocation;
  myNote : TTabNote;
  myTreeNode : TTreeNTNode;
  NewFormatURL : boolean;
  origLocationStr : string;
begin

  // Handles links that point to a "KNT location" rather than normal file:// URLs.
  // We may receive two types of links:
  // the old style link: file:///?filename.knt...
  // the new style link: file:///*filename.knt...

  p := 0;
  origLocationStr := LocationStr;

  Location := TLocation.Create;

  try
    try

      LocationStr := StripFileURLPrefix( LocationStr );

      pold := pos( KNTLOCATION_MARK_OLD, LocationStr );
      pnew := pos( KNTLOCATION_MARK_NEW, LocationStr );
      if (( pold = 0 ) and ( pnew = 0 )) then
        raise EInvalidLocation.Create( origLocationStr );
      // see which marker occurs FIRST
      // (both markers may occur, because '?' and '*' may occur within note or node names
      if ( pnew < pold ) then
      begin
        if ( pnew > 0 ) then
        begin
          NewFormatURL := true;
          p := pnew;
        end
        else
        begin
          NewFormatURL := false;
          p := pold;
        end;
      end
      else
      begin
        if ( pold > 0 ) then
        begin
          NewFormatURL := false;
          p := pold;
        end
        else
        begin
          NewFormatURL := true;
          p := pnew;
        end;
      end;

      // extract filename
      case p of
        0 : raise EInvalidLocation.Create( origLocationStr );
        1 : Location.FileName := ''; // same file as current
        else
        begin
          Location.FileName := HTTPDecode( copy( LocationStr, 1, pred( p )));
          if ( Location.FileName = NoteFile.FileName ) then
            Location.FileName := '';
        end;
      end;
      delete( LocationStr, 1, p ); // delete filename and ? or * marker

      // extract note name or ID
      p := pos( KNTLINK_SEPARATOR, LocationStr );
      case p of
        0 : begin
          if NewFormatURL then
            Location.NoteID := strtoint( LocationStr ) // get ID
          else
            Location.NoteName := HTTPDecode( LocationStr ); // get name
          LocationStr := '';
        end;
        1 : raise EInvalidLocation.Create( origLocationStr );
        else
        begin
          if NewFormatURL then
            Location.NoteID := strtoint( copy( LocationStr, 1, pred( p )))
          else
            Location.NoteName := HTTPDecode( copy( LocationStr, 1, pred( p )));
          delete( LocationStr, 1, p );
        end;
      end;

      p := pos( KNTLINK_SEPARATOR, LocationStr );
      case p of
        0 : begin
          if NewFormatURL then
            Location.NodeID := strtoint( LocationStr )
          else
            Location.NodeName := HTTPDecode( LocationStr );
          LocationStr := '';
        end;
        1 : begin
          Location.NodeName := '';
          Location.NodeID := 0;
        end;
        else
        begin
          if NewFormatURL then
            Location.NodeID := strtoint( copy( LocationStr, 1, pred( p )))
          else
            Location.NodeName := HTTPDecode( copy( LocationStr, 1, pred( p )));
        end;
      end;
      delete( LocationStr, 1, p );

      if ( LocationStr <> '' ) then
      begin
        p := pos( KNTLINK_SEPARATOR, LocationStr );
        if ( p > 0 ) then
        begin
          try
            Location.CaretPos := strtoint( copy( LocationStr, 1, pred( p )));
          except
            Location.CaretPos := 0;
          end;
          delete( LocationStr, 1, p );
          if ( LocationStr <> '' ) then
          begin
            try
              Location.SelLength := strtoint( LocationStr );
            except
              Location.SelLength := 0;
            end;
          end;
        end;
      end;

      (*
      showmessage(
        'file: ' + Location.FileName + #13 +
        'note: ' + Location.NoteName + #13 +
        'note id: ' + inttostr( Location.NoteID ) + #13 +
        'node: ' + Location.NodeName + #13 +
        'node id: ' + inttostr( Location.NodeID ) + #13 +
        inttostr( Location.CaretPos ) + ' / ' + inttostr( Location.SelLength )
      );
      *)

      // open file, if necessary
      if ( Location.FileName <> '' ) then
      begin
        if (( not fileexists( Location.FileName )) or
         ( Form_Main.NoteFileOpen( Location.FileName ) <> 0 )) then
        begin
          Form_Main.StatusBar.Panels[PANEL_HINT].Text := ' Failed to open location';
          raise Exception.CreateFmt( 'Location does not exist or file cannot be opened: "%s"', [origLocationStr] );
        end;
      end;

      // obtain NOTE
      myNote := nil;
      if ( Location.NoteID <> 0 ) then // new format
      begin
        myNote := notefile.GetNoteByID( Location.NoteID );
        if ( myNote = nil ) then
          raise Exception.CreateFmt( 'Note ID not found: %d', [Location.NoteID] );
      end
      else
      begin
        myNote := notefile.GetNoteByName( Location.NoteName );
        if ( myNote = nil ) then
          raise Exception.CreateFmt( 'Note name not found: %s', [Location.NoteName] );
      end;

      // if not current note, switch to it
      if ( myNote <> ActiveNote ) then
      begin
        Form_Main.Pages.ActivePage := myNote.TabSheet;
        Form_Main.PagesChange( Form_Main.Pages );
      end;

      // obtain NODE
      myTreeNode := nil;
      if ( myNote.Kind = ntTree ) then
      begin
        if ( Location.NodeID <> 0 ) then // new format
        begin
          myTreeNode := TTreeNote( myNote ).GetTreeNodeByID( Location.NodeID );
          if ( myTreeNode = nil ) then
            raise Exception.CreateFmt( 'Node ID not found: %d', [Location.NodeID] );
        end
        else
        begin
          myTreeNode := TTreeNote( myNote ).TV.Items.FindNode( [ffText], Location.NodeName, nil );
          if ( myTreeNode = nil ) then
            raise Exception.CreateFmt( 'Node name not found: %s', [Location.NodeName] );
        end;

        // select the node
        TTreeNote( ActiveNote ).TV.Selected := myTreeNode;

      end;

      // place caret
      with myNote.Editor do
      begin
        SelStart := Location.CaretPos;
        SelLength := Location.SelLength;
        Perform( EM_SCROLLCARET, 0, 0 );
      end;
      myNote.Editor.SetFocus;
      // StatusBar.Panels[PANEL_HINT].Text := ' Jump to location executed';

    except
      on E : EInvalidLocation do
      begin
        messagedlg( Format( 'Invalid location string: %s', [E.Message] ), mtError, [mbOK], 0 );
        exit;
      end;
      on E : Exception do
      begin
        Form_Main.StatusBar.Panels[PANEL_HINT].Text := ' Invalid location';
        messagedlg( Format( 'Error executing hyperlink: %s', [E.Message] ), mtError, [mbOK], 0 );
        exit;
      end;
    end;

  finally
    Location.Free;
  end;

end; // JumpToKNTLocation


//===============================================================
// ClickOnURL
//===============================================================
procedure ClickOnURL(const URLText: String);
var
  ShellExecResult : integer;
  Form_URLAction: TForm_URLAction;
  myURLAction : TURLAction;
  browser : string;
  URLPos : integer; // position at which the actual URL starts in URLText
  URLType, KntURL : TKNTURL;
  myURL : string; // the actual URL
  ShiftWasDown, AltWasDown, CtrlWasDown : boolean;

  function GetHTTPClient : string;
  begin
    result := '';
    if ( not KeyOptions.URLSystemBrowser ) then
      result := NormalFN( KeyOptions.URLAltBrowserPath );
    if ( result = '' ) then
     result := GetAppFromExt( ext_HTML, true );
  end; // GetHTTPClient


begin

  // this procedure must now support two methods of handling URLText
  // that is passed to it. If the link was added with richedit v. 3
  // loaded, the link text will have a different format then when
  // created with earlier versions of richedit20.dll. See
  // TForm_Main.InsertHyperlink for detailed comments on this.

  ShiftWasDown := ShiftDown and ( not _IS_FAKING_MOUSECLICK );
  CtrlWasDown := CtrlDown and ( not _IS_FAKING_MOUSECLICK );
  AltWasDown := AltDown and ( not _IS_FAKING_MOUSECLICK );
  _GLOBAL_URLText := '';

  // determine where URL address starts in URLText
  URLType := urlHTTP; // reasonable default?
  for KntURL := low( KntURL ) to high( KntURL ) do
  begin
    URLPos := pos( KNT_URLS[KntURL], URLText );
    if ( URLPos > 0 ) then
    begin
      URLType := KntURL;
      break;
    end;
  end;

  if ( URLPos > 0 ) then
    myURL := copy( URLText, URLPos, length( URLText ))
  else
    myURL := URLText; // assume it IS an URL, anyway (will try HTTP)

  ShellExecResult := maxint; // dummy

  try
    try

      myURLAction := KeyOptions.URLAction; // assume default action

      if AltWasDown then
      begin
        myURLAction := urlCopy;
      end
      else
      if CtrlWasDown then
      begin
        if ( myURLAction <> urlOpenNew ) then
          myURLAction := urlOpenNew // always open in new window if Ctrl pressed
        else
          myURLAction := urlOpen;
      end
      else
      begin
        if (( not _IS_FAKING_MOUSECLICK ) and KeyOptions.URLClickShift and ( not ShiftWasDown )) then
        begin
          Form_Main.StatusBar.Panels[PANEL_HINT].Text := ' Hold down SHIFT while clicking the URL.';
          exit;
        end;
      end;

      if ( URLType = urlFile ) then
      begin
        // various fixes, mostly with XP in mind:

        {1}
        if KeyOptions.URLFileNoPrefix then
          myURL := StripFileURLPrefix( myURL );

        {2}
        if KeyOptions.URLFileDecodeSpaces then
        begin
          myURL := HTTPDecode( myURL );

          {3}
          if ( KeyOptions.URLFileQuoteSpaces and ( pos( #32, myURL ) > 0 )) then
            myURL := '"' + myURL + '"';
        end;

        if ( myURLAction in [urlAsk] ) then
        begin
          if KeyOptions.URLFileAuto then
            myURLAction := urlOpen;
        end;
      end;

      if ( myURLAction = urlAsk ) then
      begin
        Form_URLAction := TForm_URLAction.Create( Form_Main );
        try
          // Form_URLAction.Label_URL.Caption := myURL;
          Form_URLAction.Edit_URL.Text := myURL;
          Form_URLAction.Button_OpenNew.Enabled := ( URLType in [urlHTTP, urlHTTPS] );
          if ( Form_URLAction.ShowModal = mrOK ) then
          begin
            myURLAction := Form_URLAction.URLAction;
            myURL := trim( Form_URLAction.Edit_URL.Text );
          end
          else
            myURLAction := urlNothing;
        finally
          Form_URLAction.Free;
        end;
      end;

      if ( myURLAction = urlNothing ) then
      begin
        Form_Main.StatusBar.Panels[PANEL_HINT].Text := ' URL action canceled';
        exit;
      end;

      if ( myURLAction in [urlCopy, urlBoth] ) then
      begin
        Clipboard.SetTextBuf( PChar( myURL ));
        Form_Main.StatusBar.Panels[PANEL_HINT].Text := ' URL copied to clipboard';
      end;

      // urlOpenNew is only for HTTP and HTTPS protocols
      if ( not ( URLType in [urlHTTP, urlHTTPS] )) then
      begin
        if ( myURLAction = urlOpenNew ) then
          myURLAction := urlOpen;
      end;

      if ( myURLAction in [urlOpen, urlOpenNew, urlBoth] ) then
      begin
        case URLType of
          urlFILE : begin // it may be a KNT location or a normal file URL.
            if (( pos( KNTLOCATION_MARK_NEW, myURL ) > 0 ) or ( pos( KNTLOCATION_MARK_OLD, myURL ) > 0 )) then
            begin
              // KNT location!
              _GLOBAL_URLText := myURL;
                { Why "postmessage" and not a regular procedure?
                Because we are, here, inside an event that belongs
                to the TTabRichEdit control. When a link is clicked,
                it may cause KeyNote to close this file and open
                a different .KNT file. In the process, this TTabRichEdit
                will be destroyed. If we called a normal procedure
                from here, we would then RETURN HERE: to an event handler
                belonging to a control that NO LONGER EXISTS. Which
                results in a nice little crash. By posting a message,
                we change the sequence, so that the file will be
                closed and a new file opened after we have already
                returned from this here event handler. }
              postmessage( Form_Main.Handle, WM_JumpToKNTLink, 0, 0 );
              exit;
            end
            else
            begin
              ShellExecResult := ShellExecute( 0, 'open', PChar( myURL ), nil, nil, SW_NORMAL );
            end;
          end;
          else // all other URL types
          begin
            screen.Cursor := crAppStart;
            try
              if ( myURLAction = urlOpenNew ) then
              begin
                ShellExecResult := ShellExecute( 0, 'open', PChar( GetHTTPClient ), PChar( myURL ), nil, SW_NORMAL );
              end
              else
              begin
                if ( URLType in [urlHTTP, urlHTTPS] ) then
                begin
                  if KeyOptions.URLSystemBrowser then
                    ShellExecResult := ShellExecute( 0, 'open', PChar( myURL ), nil, nil, SW_NORMAL )
                  else
                    ShellExecResult := ShellExecute( 0, 'open', PChar( GetHTTPClient ), PChar( myURL ), nil, SW_NORMAL );
                end
                else
                  ShellExecResult := ShellExecute( 0, 'open', PChar( myURL ), nil, nil, SW_NORMAL );
              end;
            finally
              screen.Cursor := crDefault;
            end;
          end;
        end;

        if ( ShellExecResult <= 32 ) then
        begin
          if (( ShellExecResult > 2 ) or KeyOptions.ShellExecuteShowAllErrors ) then
          PopupMessage( Format(
            'Error %d executing hyperlink %s: "%s"',
            [ShellExecResult, myURL, TranslateShellExecuteError(ShellExecResult)] ), mtError, [mbOK], 0 );
        end
        else
        begin
          if KeyOptions.MinimizeOnURL then
            Application.Minimize;
        end;
      end;

    except
      on E : Exception do
      begin
        messagedlg( E.Message, mtWarning, [mbOK], 0 );
      end;
    end;
  finally
    _IS_FAKING_MOUSECLICK := false;
  end;

end; // ClickOnURL



//===============================================================
// InsertURL
//===============================================================
procedure InsertURL();
var
  URLStr : string;
begin
  if ( not ( Form_Main.HaveNotes( true, true ) and assigned( ActiveNote ))) then exit;
  if Form_Main.NoteIsReadOnly( ActiveNote, true ) then exit;
  URLStr := ClipboardAsString;
  if ( InputQuery( 'Insert URL', 'Enter or paste URL:', URLStr ) and ( URLStr <> '' )) then
  begin
    case pos( ':', URLStr ) of
      0 : begin
        // assume email address
        if ( pos( '@', URLStr ) > 0 ) then
          URLStr := 'mailto:' + URLStr;
      end;
      2 : begin
        // could be a filename
        if ( upcase( URLStr[1] ) in ['A'..'Z'] ) then
        begin
          InsertFileOrLink( URLStr, true );
          exit;
        end;
      end;
    end;
    URLStr := FileNameToURL( URLStr );
    ActiveNote.Editor.SelText := URLStr + #32;
    ActiveNote.Editor.SelLength := 0;
  end;
end; // Insert URL



(*
procedure TForm_Main.InsertHyperlink(
  const aLinkType : TLinkType;
  aLinkText, aLinkTarget : string;
  const aLocation : TLocation );
var
  InitialSelStart : integer;
  TextLen, TargetLen : integer;
  Location : TLocation;
begin
  { Inserts a hyperlink in active note.
    Only RichEdit v.3 supports .Link and .Hidden properties.
    For RichEdit 2, we can only display full link address,
    and cannot use not or node IDs
  }

  { Syntax of the "KeyNote location" link:
    1) OLD STYLE (used in KeyNote versions earlier than 1.1
       and still used when RichEditVersion < 2)

       (a)
       file:///filename.knt?NoteName|NodeName|CaretPos|SelLength

       Filename.knt may be blank if links points to current file.
       Only NoteName is required.
       The '?' character is invalid in filenames, so it tells us
       this is a hyperlink to a KeyNote location, not a normal
       link to local file.

       The problem with this scheme is that it fails when there
       is more than one note (or tree node) by the same name.

       (b)
       Begining with version 1.1, we use note and node IDs instead:
       file:///filename.knt|NoteID|NodeID|CaretPos|SelLength
       The '|' character has the same function as '?' in (a),
       (also invalid in filenames), but it also tells us this
       is the new type of link, using Note IDs rather than names.
       However, we can only use this methof with RichEdit v. 3
       (see below) because it allows us to have an arbitrary description
       assigned to an URL. In RichEdit v. 2 we can only display the
       URL itself, so we must use note and node names rather than IDs,
       so as to have meaningful links (otherwise, we'd have links
       such as "file:///filename.knt?23|45" which are meaningless).

    2) NEW STYLE, used only if RichEditVersion >= 3

       file:///filename.knt*NoteID|NodeID|CaretPos|SelLength

       (the '*' replaces the '?' and indicates new format)

       This link format uses unique note and node IDs.
       The URL is actually hidden and the displayed link
       is any user-defined text.

       If no link text is specified, it is generated automatically.

       The address part is formatted using hidden text and follows
       the link description:

       Yahoo websitehttp://www.yahoo.com
       +--------------------------------+ has .Link property
                    +-------------------+ has .Hidden property
       This way, when the link is clicked, the full text of the link
       will be passed to OnURLClick handler. Note that there is no
       separator character that divides the link text from link URL,
       because in the editor only the text link is displayed, and
       the user may type in any character she wishes to. (We could use
       an nprintable character, though?)

    Notes: all strings are URL-encoded: filename.knt,
    as well as note name and node name.

  }
  {
    LocationString := 'file:///' + LocationString + '?' +
      FileNameToURL( _KNTLocation.NoteName ) + KNTLINK_SEPARATOR +
      FileNameToURL( _KNTLocation.NodeName ) + KNTLINK_SEPARATOR +
      inttostr( _KNTLocation.CaretPos ) + KNTLINK_SEPARATOR +
      inttostr( _KNTLocation.SelLength );
  }

  if ( not assigned( ActiveNote )) then exit;

  InitialSelStart := ActiveNote.Editor.SelStart;

  ActiveNote.Editor.Lines.BeginUpdate;
  try
    if (( _LoadedRichEditVersion > 2 ) and KeyOptions.UseNewStyleURL ) then
    begin
      // use new URL syntax
      case aLinkType of
        lnkURL : begin
          if ( aLinkText = '' ) then
            aLinkText := aLinkTarget;
          aLinkTarget := FileNameToURL( aLinkTarget );
        end;
        lnkEmail : begin
          if ( aLinkText = '' ) then
          begin
            aLinkText := aLinkTarget;
            if ( pos( 'mailto:', aLinkText ) = 1 ) then
              delete( aLinktext, 1, 7 );
          end;
          aLinkTarget := FileNameToURL( aLinkTarget );
        end;
        lnkFile : begin
          if ( aLinkText = '' ) then
            aLinkText := extractfilename( aLinkTarget );
          aLinkTarget := FileNameToURL( aLinkTarget );
        end;
        lnkKNT : begin

        end;
      end; // case

      // format the hyperlink text using .Link and .Hidden properties
      TextLen := length( aLinkText );
      TargetLen := length( aLinkTarget );

      ActiveNote.Editor.SelText := aLinkText+aLinkTarget+#32;
      ActiveNote.Editor.SelAttributes.Link := false; // in case we were in link already
      ActiveNote.Editor.SelAttributes.Hidden := false; // in case we were in hidden font already

      // select whole thing and mark as link, excluding the final space
      ActiveNote.Editor.SelLength := TextLen+TargetLen;
      ActiveNote.Editor.SelAttributes.Link := true;

      // now select the LinkTarget part and mark it as hidden
      ActiveNote.Editor.SelStart := InitialSelStart + TextLen;
      ActiveNote.Editor.SelLength := TargetLen;
      ActiveNote.Editor.SelAttributes.Hidden := true;

      // clear any selection
      ActiveNote.Editor.SelStart := InitialSelStart;
      ActiveNote.Editor.SelLength := 0;

    end
    else
    begin
      // use old URL syntax
      case aLinkType of
        lnkKNT : begin
        end
        else
        begin
          ActiveNote.Editor.SelText := FileNameToURL( aLinkTarget ) + #32;
          ActiveNote.Editor.SelLength := 0;
        end;
      end;
    end;

  finally
    ActiveNote.Editor.Lines.EndUpdate;
    NoteFile.Modified := true;
    UpdateNoteFileState( [fscModified] );
  end;


end; // InsertHyperlink
*)

(*

procedure TForm_Main.CreateHyperlink;
var
  Form_Hyperlink : TForm_Hyperlink;
  s : string;
begin
  if ( not assigned( ActiveNote )) then exit;
  if NoteIsReadOnly( ActiveNote, true ) then exit;

  Form_Hyperlink := TForm_Hyperlink.Create( self );
  try

    Form_Hyperlink.LinkText := ActiveNote.Editor.SelText;
    Form_Hyperlink.Edit_Text.Enabled := (( _LoadedRichEditVersion > 2 ) and KeyOptions.UseNewStyleURL );
    Form_Hyperlink.LB_Text.Enabled := Form_Hyperlink.Edit_Text.Enabled;

    if ( Form_Hyperlink.ShowModal = mrOK ) then
    begin
      { New syntax for hyperlinks - requires RichEdit v. 3
      hyperlinks in RTF text are formatted as follows:
      <LINK>Link title<HIDDEN>target address</HIDDEN></LINK>
      "Link" and "Hidden" are properties of RxRichEdit.SelAttributes,
      i.e. ActiveNote.Editor.SelAttributes.
      That way, when the link is clicked, the OnURLClick event handler
      gives us the complete text of the link. We'll then have to search
      for the protocol identifier, e.g. http://, mailto:, file:///, etc.
      }

      with Form_Hyperlink do
      begin

        s := lowercase( LinkTarget );
        case LinkType of
          lnkURL : begin
            // test the URL, esp. see if it has a scheme prefix
            if ( pos( ':/', LinkTarget ) = 0 ) then
            begin
              if ( pos( 'ftp', LinkTarget ) = 1 ) then
                LinkTarget := 'ftp://' + LinkTarget
              else
                LinkTarget := 'http://' + LinkTarget; // [x] very simplistic
            end;
          end;
          lnkEmail : begin
            if ( pos( 'mailto:', s ) <> 1 ) then
              LinkTarget := 'mailto:' + LinkTarget;
          end;
          lnkFile : begin
            // may be a file or a folder
            if fileexists( LinkTarget ) then
            begin
              LinkTarget := NormalFN( LinkTarget );
            end
            else
            if DirectoryExists( Linktarget ) then
            begin
              LinkTarget := ProperFolderName( LinkTarget );
            end
            else
            begin
              // not a file and not a folder, must be an error
              MessageDlg( 'No file or folder by the specified name exists: ' + LinkTarget, mtError, [mbOK], 0 );
              exit;
            end;
            LinkTarget := 'file:///' + LinkTarget;
          end;
          lnkKNT : begin
            // we do not use LinkTarget here. Instead, we use the
            // location that was last marked and stored in _KntLocation.
          end;
        end;

        InsertHyperlink( LinkType, LinkText, LinkTarget, _KNTLocation );

      end;
    end;
  finally
    Form_Hyperlink.Free;
  end;
end; // CreateHyperlink
*)


end.