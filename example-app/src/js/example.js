import { HttpLocalServerSwifter } from '@cappitolian/http-local-server-swifter';

window.testEcho = () => {
    const inputValue = document.getElementById("echoInput").value;
    HttpLocalServerSwifter.echo({ value: inputValue })
}
