import 'package:flutter/material.dart';
import 'package:english_words/english_words.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:snapping_sheet/snapping_sheet.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

enum Status {
  Uninitialized,
  Guest,
  Authenticated,
  Authenticating,
  Unsuccessful
}

class UserRepository with ChangeNotifier {
  FirebaseAuth _auth;
  User _user;
  Status _status = Status.Uninitialized;
  String _currentUserEmail = "";
  Image _avatar;

  UserRepository.instance() : _auth = FirebaseAuth.instance {
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  Status get status => _status;
  User get user => _user;
  String get currentUserEmail => _currentUserEmail;
  Image get avatar => _avatar;


  Future<bool> signIn(String email, String password) async {
    try {
      _status = Status.Authenticating;
      //When Authenticating => change to loading bar
      notifyListeners();
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      _currentUserEmail = email;
      notifyListeners();
      //Update avatar
      _avatar = Image.network(await getUserAvatarUrl(email));
      _updateCollection(email);
      _saved.clear();
      return true;
    } catch (e) {
      _status = Status.Unsuccessful;

      notifyListeners();
      return false;
    }
  }

  void _addOnePair(String currentUserEmail, WordPair pair) {
    String docName = pair.asPascalCase;
    FirebaseFirestore.instance.collection(currentUserEmail).doc(docName).set({
    });
  }

  void notifyListenersAux(){
    notifyListeners();
  }

  void _removeOnePair(String currentUserEmail, WordPair pair) {
    String docName = pair.asPascalCase;
    FirebaseFirestore.instance..collection(currentUserEmail).doc(docName).delete();
    notifyListeners();
  }

  Future<bool> signUpAndSignIn(String email, String password) async {
    try {
      _status = Status.Authenticating;
      //When Authenticating => change to loading bar
      notifyListeners();
      await _auth.createUserWithEmailAndPassword(email: email, password: password);
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      _currentUserEmail = email;
      notifyListeners();

      //Update default avatar
      var _avatarUrl = await getDefaultAvatarUrl();
      updateAvatar(_avatarUrl);
      _avatar = Image.network(_avatarUrl);
      _updateCollection(email);
      _saved.clear();
      return true;
    } catch (e) {
      _status = Status.Unsuccessful;
      notifyListeners();
      return false;
    }
  }

  Future signOut() async {
    _auth.signOut();
    _status = Status.Guest;
    _currentUserEmail = "";
    _avatar = null;
    //When Signing out => regular main screen. will be in OnPressed
    notifyListeners();
    return Future.delayed(Duration.zero);
  }

  void updateAvatar(String _avatarFilePath) async {
    await (FirebaseStorage.instance.ref('UsersAvatars')
        .child(_currentUserEmail)
        .putFile(File(_avatarFilePath)));
    _avatar = Image.file(File(_avatarFilePath));
    notifyListeners();//So that the new avatar will be showen immediately
  }

  Future<String> getUserAvatarUrl(String email) async {
    String result;
    try {
      result = await (FirebaseStorage.instance.ref('UsersAvatars')
          .child(email)
          .getDownloadURL());
    }
    catch(e){
      result = await getDefaultAvatarUrl();
    }
    return result;
  }

  Future<String> getDefaultAvatarUrl() async {
    return await (FirebaseStorage.instance.ref('UsersAvatars')
        .child('DefaultAvatar.png')
        .getDownloadURL());
  }

  Future<void> _onAuthStateChanged(User firebaseUser) async {
    if (firebaseUser == null) {
      _status = Status.Unsuccessful;
    } else {
      _user = firebaseUser;
      _status = Status.Authenticated;
      //When Authenticated => return to home page and put exit_to_app icon
    }
    notifyListeners();
  }
}

void _updateCollection(String currentUserEmail) {
  //Enter all the local saved to the cloud collection
  _saved.forEach((WordPair pair) {
    String docName = pair.asPascalCase;
    FirebaseFirestore.instance.collection(currentUserEmail).doc(docName).set({
    });
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(App());
}

class App extends StatelessWidget {
  final Future<FirebaseApp> _initialization = Firebase.initializeApp();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
              body: Center(
                  child: Text(snapshot.error.toString(),
                      textDirection: TextDirection.ltr)));
        }
        if (snapshot.connectionState == ConnectionState.done) {
          return MyApp();
        }
        return Center(child: CircularProgressIndicator());
      },
    );
  }
}


class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
        create: (_) => UserRepository.instance(),
        child: Consumer(builder: (context, UserRepository user, _) {
          return MaterialApp(
            title: 'Startup Name Generator',
            theme: ThemeData(
              primaryColor: Colors.red,
            ),
            home: RandomWords(),
          );
        }));
  }
}

final TextStyle _biggerFont = const TextStyle(fontSize: 18); // NEW
final _saved = Set<WordPair>();

class RandomWords extends StatefulWidget {
  @override
  _RandomWordsState createState() => _RandomWordsState();
}

class _RandomWordsState extends State<RandomWords> with SingleTickerProviderStateMixin {
  var _snappingSheetController = SnappingSheetController();

  final List<WordPair> _suggestions = <WordPair>[];

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserRepository>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Startup Name Generator'),
        actions: [
          IconButton(
              icon: Icon(Icons.favorite),
              onPressed: () {
                if (!(user.status == Status.Authenticated)) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => SavedSuggestionsPage()),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => GetAllUserPairsRealtime()),
                  );
                }
              }),

//_RandomWordsState
          Consumer(
            builder: (context, UserRepository user, _) {
              switch (user.status) {
                case Status.Authenticated:
                  return IconButton(
                      icon: Icon(Icons.exit_to_app),
                      onPressed: () {
                        user.signOut();
                        _saved.clear();
                      });
                default:
                  return Builder(
                    builder: (context) =>
                        IconButton(
                            icon: Icon(Icons.login),
                            onPressed: () {
                              TextEditingController _email;
                              TextEditingController _password;
                              TextEditingController _password2;

                              final _formKey = GlobalKey<FormState>();
                              final _key = GlobalKey<ScaffoldState>();

                              _email = TextEditingController(text: "");
                              _password = TextEditingController(text: "");

                              //Pushing the login screen
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (BuildContext context) {
                                    return Scaffold(
                                      key: _key,
                                      appBar: AppBar(
                                        title: Text('Login'),
                                      ),
                                      body: Form(
                                        key: _formKey,
                                        child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                12.0, 32.0, 8.0, 8.0),
                                            child: Column(
                                              children: <Widget>[
                                                Text(
                                                    'Welcome to Startup Names Generator, please log in below\n\n',
                                                    style: TextStyle(
                                                        fontSize: 16)),
                                                TextField(
                                                  controller: _email,
                                                  decoration: InputDecoration(
                                                    labelText: "Email",
                                                  ),
                                                ),
                                                Divider(),
                                                TextField(
                                                  controller: _password,
                                                  obscureText: true,
                                                  decoration: InputDecoration(
                                                    labelText: "Password",
                                                  ),
                                                ),
                                                user.status ==
                                                    Status.Authenticating
                                                    ? Center(
                                                    child:
                                                    Padding(
                                                      padding: const EdgeInsets
                                                          .fromLTRB(
                                                          0.0, 27.0, 0.0, 8.0),
                                                      child: CircularProgressIndicator(),
                                                    ))
                                                    : Column(
                                                  children: [
                                                    Padding(
                                                      padding: const EdgeInsets
                                                          .fromLTRB(
                                                          0.0, 20.0, 0.0, 8.0),
                                                      child: Material(
                                                        elevation: 5.0,
                                                        borderRadius:
                                                        BorderRadius.circular(
                                                            30.0),
                                                        color: Colors.red,
                                                        child: MaterialButton(
                                                          onPressed: () async {
                                                            if (_formKey
                                                                .currentState
                                                                .validate()) {
                                                              if (!await user
                                                                  .signIn(
                                                                  _email.text,
                                                                  _password
                                                                      .text)) {
                                                                _key
                                                                    .currentState
                                                                    .showSnackBar(
                                                                    SnackBar(
                                                                      content: Text(
                                                                          "There was an error logging into the app"),
                                                                    ));
                                                              } else {
                                                                Navigator.of(
                                                                    context)
                                                                    .pop();
                                                              }
                                                            }
                                                          },
                                                          child: Text(
                                                            "                                    Log in                                        ",
                                                            style: TextStyle(
                                                                color:
                                                                Colors.white,
                                                                fontSize: 16),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    Padding(
                                                      padding: const EdgeInsets
                                                          .fromLTRB(
                                                          0.0, 14.0, 0.0, 8.0),
                                                      child: Material(
                                                        elevation: 5.0,
                                                        borderRadius:
                                                        BorderRadius.circular(
                                                            30.0),
                                                        color: Colors.teal,
                                                        child: MaterialButton(
                                                          onPressed: () async {
                                                            _password2 =
                                                                TextEditingController(
                                                                    text: "");
                                                            showModalBottomSheet<
                                                                void>(
                                                              context: context,
                                                              builder: (
                                                                  BuildContext context) {
                                                                return Container(
                                                                  height: 230,
                                                                  child: Center(
                                                                    child: Column(
                                                                      children: <
                                                                          Widget>[
                                                                        Padding(
                                                                          padding: const EdgeInsets
                                                                              .fromLTRB(
                                                                              8.0,
                                                                              18.0,
                                                                              8.0,
                                                                              4.0),
                                                                          child: const Text(
                                                                              'Please confirm your password below:'),
                                                                        ),
                                                                        Divider(),
                                                                        Padding(
                                                                          padding: const EdgeInsets
                                                                              .fromLTRB(
                                                                              12.0,
                                                                              16.0,
                                                                              8.0,
                                                                              8.0),
                                                                          child: TextFormField(
                                                                            controller: _password2,
                                                                            obscureText: true,
                                                                            decoration: InputDecoration(
                                                                              errorText: ((_password2
                                                                                  .text !=
                                                                                  "") &&
                                                                                  (_password
                                                                                      .text !=
                                                                                      _password2
                                                                                          .text))
                                                                                  ? "Passwords must match"
                                                                                  : null,
                                                                              labelText: "Password",
                                                                            ),
                                                                          ),
                                                                        ),
                                                                        RaisedButton(
                                                                            color: Colors
                                                                                .teal,
                                                                            child: const Text(
                                                                                'Confirm',
                                                                                style: TextStyle(
                                                                                    color:
                                                                                    Colors
                                                                                        .white)),
                                                                            onPressed: () async {
                                                                              if ((_password2
                                                                                  .text !=
                                                                                  "") &&
                                                                                  _password
                                                                                      .text ==
                                                                                      _password2
                                                                                          .text) {
                                                                                //Do the sign up and sign in
                                                                                if (await user
                                                                                    .signUpAndSignIn(
                                                                                    _email
                                                                                        .text,
                                                                                    _password
                                                                                        .text))
                                                                                  Navigator
                                                                                      .of(
                                                                                      context)
                                                                                      .pop();
                                                                                Navigator
                                                                                    .of(
                                                                                    context)
                                                                                    .pop();
                                                                              }
                                                                              /*else {
                                                                                  //Nothing, We can assume input is in valid format
                                                                                }*/
                                                                            }
                                                                        )
                                                                      ],
                                                                    ),
                                                                  ),
                                                                );
                                                              },
                                                            );
                                                          },
                                                          //}
                                                          child: Text(
                                                            "                   New user? Click to sign up                    ",
                                                            style: TextStyle(
                                                                color:
                                                                Colors.white,
                                                                fontSize: 16),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),

                                              ],
                                            )),
                                      ),
                                    );
                                  }, // ...to here.
                                ),
                              );

                              @override
                              void dispose() {
                                _email.dispose();
                                _password.dispose();
                                _password2.dispose();
                                super.dispose();
                              }
                            }),
                  );
              }
            },
          ),
        ],
      ),
      /*Consumer(
        builder: (context, UserRepository user, _) {
          return*/
      body: user.status != Status.Authenticated ?
      _buildSuggestions()
          : SnappingSheet(
        sheetAbove: SnappingSheetContent(
          child: Padding(
            padding: EdgeInsets.only(bottom: 20.0),
            child: Align(
              alignment: Alignment(0.90, 1.0),
            ),
          ),
        ),
        snappingSheetController: _snappingSheetController,
        snapPositions: const [
          SnapPosition(positionPixel: 0.0,
              snappingCurve: Curves.elasticOut,
              snappingDuration: Duration(milliseconds: 850)),
          SnapPosition(positionFactor: 0.22),
          SnapPosition(positionFactor: 0.22),
        ],
        child: _buildSuggestions(),
        grabbingHeight: 53,
        grabbing: InkWell(
          child: Container(
              decoration: BoxDecoration(color: Colors.grey),
              child: ListTile(
                title: Text("Welcome back, ${user.currentUserEmail}"),
                trailing: Icon(Icons.keyboard_arrow_up),
              )),
          onTap: () {
            setState(() {
              if (_snappingSheetController.snapPositions.last !=
                  _snappingSheetController.currentSnapPosition) {
                _snappingSheetController.snapToPosition(
                    _snappingSheetController.snapPositions.last);
              }
              else{
                _snappingSheetController.snapToPosition(
                    _snappingSheetController.snapPositions.first);
              }
            });
          },
        ),
        sheetBelow: SnappingSheetContent(
            heightBehavior: SnappingSheetHeight.fit(),
            child: SheetContent()
        ),
      ),
    );
  }

  Widget _buildSuggestions() {
    return ListView.builder(
        itemBuilder: (BuildContext _context, int i) {
          // Add a one-pixel-high divider widget before each row
          // in the ListView.
          if (i.isOdd) {
            return Divider();
          }
          final int index = i ~/ 2;
          // If you've reached the end of the available word
          if (index >= _suggestions.length) {
            // ...then generate 10 more and add them to the
            _suggestions.addAll(generateWordPairs().take(10));
          }
          return _buildRow(_suggestions[index]);
        });

  }

  Widget _buildRow(WordPair pair) {
    final alreadySaved = _saved.contains(pair); // NEW
    return ListTile(
      title: Text(
        pair.asPascalCase,
        style: _biggerFont,
      ),

      trailing: Icon(
        alreadySaved ? Icons.favorite : Icons.favorite_border,
        color: alreadySaved ? Colors.red : null,
      ),

      onTap: () {
        setState(() {
          final user2 = Provider.of<UserRepository>(context, listen: false);
          if (alreadySaved) {
            _saved.remove(pair);
            if (user2.status == Status.Authenticated) {
              user2._removeOnePair(user2.currentUserEmail, pair);
            }
            user2.notifyListenersAux();
          } else {
            _saved.add(pair);
            if (user2.status == Status.Authenticated) {
              user2._addOnePair(user2.currentUserEmail, pair);
            }
          }

        });
      }, // ... to here.
    );
  }
}



class SheetContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserRepository>(context);

    //Consumer<User
    return Container(
      color: Colors.white,
      child: Container(
          child: ListView(
              children: [
                ListTile(leading: CircleAvatar(radius: 30,
                  backgroundColor: Colors.transparent,
                  ///check if user has a photo...
                  backgroundImage: user._avatar!=null ? user._avatar.image : null
                  ),
              title: Padding(
                padding: const EdgeInsets.fromLTRB(0.0, 14.0, 0.0, 10.0),
                child: Text(user.currentUserEmail, style: TextStyle(fontSize: 24)),
              ),
              subtitle: Container(
                  height: 22,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0.0, 0.0, 130.0, 0.0),
                    child: RaisedButton(
                      color: Colors.teal,
                      child: Text("Change Avatar", style: TextStyle(fontSize: 16)),
                        textColor: Colors.white,
                        onPressed: () async {
                          PickedFile newAvatar = await (ImagePicker().getImage(source: ImageSource.gallery));
                          if (newAvatar == null) {
                            //If the user dismisses the dialog without
                            // selecting an image, show a snack bar with the message “No image selected”.
                            Scaffold.of(context).showSnackBar(SnackBar(
                              content: Text("No image selected"),
                            ));
                          } else {
                            user.updateAvatar(newAvatar.path);
                            user.notifyListenersAux();
                          }
                        },
                    ),
                  )),
            )
          ]))

    );
  }
}

class SavedSuggestionsPage extends StatefulWidget {
  @override
  _SavedSuggestionsPageState createState() => _SavedSuggestionsPageState();
}

class _SavedSuggestionsPageState extends State<SavedSuggestionsPage> {
  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserRepository>(context);

    /*return Consumer<UserRepository>(
        builder: (context, user, _) {*/
          final tiles = _saved.map(
                (WordPair pair) {
              return Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8.0, 0, 8.0),
                  child: ListTile(
                    title: Text(
                      pair.asPascalCase,
                      style: _biggerFont,
                    ),
                    trailing: Builder(
                      builder: (context) =>
                          IconButton(
                            icon: Icon(Icons.delete_outline),
                            onPressed: () {
                              setState(() {
                                _saved.remove(pair);
                                user.notifyListenersAux();
                              });
                            },
                          ),
                    ),
                  ));
            },
          );

    final divided = ListTile.divideTiles(
      context: context,
      tiles: tiles,
    ).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Saved Suggestions'),
      ),
      body: ListView(children: divided)
    );
          //});
  }
}

class GetAllUserPairsRealtime extends StatelessWidget {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  Stream<List<QueryDocumentSnapshot>> _getAllUserPairs(
      String currentUserEmail) {
    return db.collection(currentUserEmail).snapshots().map(
        (value) => value.docs); // Map the query result to the list of documents
  }

  Future<void> _deletePairDoc(String currentUserEmail, String docIdToDelete) {
    return db.collection(currentUserEmail).doc(docIdToDelete).delete();
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserRepository>(context);

    return StreamBuilder<List<QueryDocumentSnapshot>>(
      stream: _getAllUserPairs(user.currentUserEmail),
      builder: (context, AsyncSnapshot<List<QueryDocumentSnapshot>> snapshot) {
        if (snapshot.hasData) {
          final List<QueryDocumentSnapshot> data = snapshot.data;

          return Scaffold(
            appBar: AppBar(
              title: Text('Saved Suggestions'),
            ),
            body: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(0, 8.0, 0, 8.0),
                  itemBuilder: (context, index) {
                    final docID = data[index].id;
                    return ListTile(
                      title: Text(
                          '$docID',
                        style: _biggerFont),
                      trailing: IconButton(
                        icon: Icon(Icons.delete_outline),
                        onPressed: () {
                          _deletePairDoc(user.currentUserEmail, docID);
                          user.notifyListenersAux();
                          WordPair pairToDelete;
                          _saved.forEach((WordPair pair) {
                            String currentPair = pair.asPascalCase;
                            if(currentPair==docID){
                              pairToDelete = pair;
                            }
                          });
                          if(pairToDelete!=null) {
                            _saved.remove(pairToDelete);
                            user.notifyListenersAux();
                          }

                        },
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => Divider(),
                  itemCount: data.length),

          );
        }

        return Scaffold(
            body: Center( child:
        CircularProgressIndicator()));

      },
    );
  }
}
