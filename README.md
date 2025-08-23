# roku_app
## Enable Developer Mode on Roku

1)  Turn on your Roku device and ensure it’s connected to your TV and network.
2)  On the Roku remote, press the following sequence (fairly quickly):

      <code>Home (3x) + Up (2x) + Right + Left + Right + Left + Right </code>

3)  The Developer Settings screen will appear.
4)  Select Enable installer and restart.
5)  Read and accept the Developer Agreement.
6)  Set a Webserver password (you’ll use this to log in later).
7)  The Roku will restart, and Developer Mode will now be enabled.

      <code>Note the Roku’s IP address shown after reboot (e.g., 192.168.1.25).</code>

## Prepare Your Application
1)  Put your channel icon/spash screen images in the /images folder
2)  Open the manifest and change the Title and the links to the image files
3)  Roku apps are packaged as ZIP files containing the app code (manifest along with the source, images, and components folders).
4)  Ensure your project is zipped properly before upload.
5)  To get debugging, open a terminal (Linux) and type:

     <code>telnet 192.168.1.100 8085</code>

## Upload the Application
1)  Open a web browser on your computer that’s on the same network as the Roku.
2)  Enter the Roku’s IP address in the browser (e.g., http://192.168.1.25).
3)  A Developer Application Installer login page will appear.
    -  Username: rokudev
    -  Password: (the one you set in Developer Settings).
4)  On the installer page:
    -  Click Upload, select your app ZIP file.
    -  Click Install with zip.
5)  The Roku will install and immediately launch your app.

## Re-Accessing Developer Mode
1)  To upload a new version, just return to the Developer Application Installer page at your Roku’s IP address.
2)  Each new upload replaces the previous version.

## Notes & Limitations
Developer Mode supports only one sideloaded application at a time. Uploading another will overwrite the current one.


If you ever disable Developer Mode, your sideloaded app will be removed.
