## SessionManagerを作ってみる

[参考文献](https://leben.mobi/go/session-design/practice/web/)

構成について

```sh
.
├── main.go
└── sessions
    ├── manager.go
    └── session.go
```
<table>
  <tr>
    <th>ファイル名</th>
    <th>機能として実装するべき内容</th>
  </tr>
  <tr>
    <td>manager.go</td>
    <td></td>
  </tr>
  <tr>
    <td>session.go</td>
    <td><li>セッション構造体の定義</li>
        <li>セッションのインスタンス化</li>
        <li>セッション変数の取り扱い</li>
    </td>
  </tr>
</table>
では早速 <span style="color: red; ">manager.go</span>から実装していきます。
今回使用するパッケージについては以下とします。

### セッションマネージャの実装を行う

- [ ] セッションマネージャ構造体の定義を行う

	Map型で定義を行っている理由についてはまずキーとして一意となるセッションIDを持たせ、
	そのキーに紐づくセッション情報を格納したいため

	```go
	type Manager struct {
		database map[string]interface{}
	}
	```
- [ ] `Manager構造体`の初期化を行うためのコンストラクタを作成する。

	コンストラクタであるため、このファイルが読み込まれるタイミングで初期化が行われる。

	```go
	var manager Manager

	func NewManager() *Manager {
		return &manager
	}
	```
- [ ] 新規セッションIDの払い出しを行う関数を作成する

	まずこの関数みて着目するべきところは`rand.Readerという`ioパッケージのインスタンス変数を利用していることです。
	なぜ`crypto/randパッケージ`がReaderインスタンス変数を利用できるかについては[Goの公式パッケージDOC](https://golang.org/pkg/crypto/rand/#pkg-variables)をみることで理解できます。あとは64バイトでゼロクリアされた配列にcyrpto/randで擬似乱数を生成してbase64で文字列にエンコードすることでセッションIDを払い出すことができます。

	ドキュメントの一部分を抜粋します。
	```go
	var Reader io.Reader

	Reader is a global, shared instance of a cryptographically secure random number generator.
	```
	上記からReaderは共有インスタンス変数としてcryptographicallyで利用できると謳っておりました。これにより`cyrpto/rand.Reader`の解釈ができると思います。

	```go
	func (m * Manager) PayLoadNewSessionId() string {
		b := make([]byte, 64)
		if _, err := io.ReadFull(rand.Reader, b); err := nil {
			return ""
		}
		return base64.URLEncoding.EncodeToString(b)
	}
	```

- [ ] 新規セッションの生成を行う

	まず、Newメソッドの第一引数である`*http.Request`についてみていきます。この形の解釈としは
	`net/httpパッケージの中で定義されているRequest構造体`を示していることになります。

	実際に[Request構造体がどのような形状になっているかは下記のコード](https://github.com/golang/go/blob/master/src/net/http/request.go#L108)を参照ください。

	次に`r.Cookie()メソッド`についてみていきます。まずこのメソッドのRequest構造体に紐づくものであることがわかると思いますので[メソッドの定義](	https://github.com/golang/go/blob/master/src/net/http/request.go#L422)をみます。

	下記はメソッドを抜粋したものです。
	ソースをみるとfor文でreadCookies関数から取得したCookieのリストを回していることがわかります。せっかくですのでもう少し詳しくみてみます。

	```go
	func (r *Request) Cookie(name string) (*Cookie, error) {
		for _, c := range readCookies(r.Header, name) {
			return c, nil
		}
		return nil, ErrNoCookie
		}
	```
	先ほどの[readCookies関数](https://github.com/golang/go/blob/master/src/net/http/cookie.go#L237)の話に戻します。この関数の第一引数として渡している`r.Header`という値に注目します。これはリクエストヘッダと呼ばれるHTTP通信の際に付与されるヘッダーであり
	通信の大まかな要求が記述されているものとして捉えてください。

	では関数内部の話に戻します。
	関数の237行目に着目してください。
	`lines := h["Cookie"]`というコードでHeaderマップから"Cookieをキーとして`リクエストライン`が存在するか判定を行っております。

	**※リクエストラインとは...**

	[HTTPリクエストの中で記述されているリクエストヘッダーの一行目の部分を示し、HTTPリクエスト全体の概要が大まかに記述されております。](https://wa3.i-3-i.info/word1843.html)

	その後はバリデーション処理やパース処理を行い問題がなければCookie構造体配列にCookie情報を詰めてリターンしています。

	```go
	func (m *Manager) New(r.*http.Request, cookieName string) (*Session , error) {
		cookie, err := r.Cookie(cookieName)
		if err != nil && m.Exists(cookie.Value) {
			return nil, errors.New("Session Id Was AllReady Issued")
		}

    // このセッション初期化関数はsession.goで実装する
		session := NewSession(m, cookieName)
		session.Id = m.PayLoadNewSessionId()
		session.Request = r

		return session, nil
	}

	```
- [ ] クライアントとサーバ側にセッションの保存を行う

  ```go
  func (m *Manager) Save(r *http.Request, w http.ResponseWriter, session *Session) err {
    m.database[session.Id] = session

    c := &http.Cookie{
      Name: session.Name(),
      Value: session.Id,
    }
    http.SetCookie(session.writer, c)
    return nil
  }

  ```
- [ ] 既存セッションのチェックを行う汎用メソッド

  ```go
  func (m *Manager) IsExists(sessionId string) bool {
    _,  s := m.database[sessionId]  
    return s
  }
  ```
- [ ] 既存セッション情報の取得を行う

  クライアント側のセッション情報と突き合わせを行います。
  クライアント側で管理しているクッキー情報を取得し、その中からセッションIDの抽出を行います。

  次に取得したセッションIDをキーとしてサーバ側で保有しているセッション情報であるかの突き合わせを行います。
  なければ存在しないセッションIdであることをエラーとしてユーザに促します。
  突き合わせの結果存在するセッション情報であればその値(session構造体)をinterface{}から取り出します。

  ```go
  func (m *Manager) GetSessionInfo(r *http.Request , cookieName string) (*Session, error) {
    cookie , err := r.Cookie(cookieName)
    if err != nil {
      return nil, err
    }
    sessionId := cookie.Value
    buffer, exists := m.database[sessionId]
    if ! exists {
      return nil, errors.New("Invalid Session Id")
    }

    session := buffer.(*Session)
    session.request = r
    return session , nil
  }
  ```
- [ ] セッショ情報の破棄を行う

  ```go
  func (m *Manager) DestroySessionInfo(sessionId string) {
    delete(m.database, sessionId)
  }
  ```

### 個々のセッションに関する機能の実装

  - [ ] セッション構造体の定義を行う

    ここで大切なフィールドは`manager`と`Value`になります。
    それぞれの役割について簡単に述べていきます。

    ```
    manager: 複数のセッションを管理するための仕組みを提供するオブジェクト
    Value  : セッションに紐づけたい任意の情報を格納するためのマップでセッション変数に該当する
    ```
    ```go
    type Session struct {
      cookieName string
      Id      string
      manager *manager
      request *http.Request
      writer  httpResponseWriter
      Value   map[string]interface{}
    }
    ```
  - [ ] 新規セッションの作成

    ここで`セッションID`, `HTTPリクエスト`、`ResponseWriter`等の初期化は行わず
    これらの値についてはセッションマネージャー側に持たせます。
    ```go
    func NewSession(manager *Manager, cookieName string) *Session {
      // Session 構造体の初期化を行っている
      return &Session{
        cookieName: cookieName,
        Manager: manager,
        Value  : map[string]interface{}{},
      }
    }
    ```

  - [ ] セッションの開始を行う

    既存のセッション情報であるかをセッションマネージャ側のメソッドで判断を行います。
    次にこのメソッドから返却されるセッション構造体をポインタで参照することにより
    セッション構造体が実体として存在するかを見極めます。

    ```go
    session, err = manager.GetSessionInfo(ctx.Request, cookieName)
    if *session == nil {

    }
    ```
    ```go
    func BeginSession(sessionName, cookieName string, manager *Manager) gin.HundlerFunc {
      return func (ctx *gin.Context){
          var session *Session
          var err error
          session, err = manager.GetSessionInfo(ctx.Request, cookieName)
          if *session != nil {
            session , err = manager.New(ctx.Request, cookieName)
            if err != nil {
              log.Println(err.Error())
              ctx.Abort()
            }
          }
          session.writer =ctx.Writer
          ctx.Set(sessionName, session)
          defer context.Clear(ctx.Request)
          ctx.Next()
      }
    }
    ```
